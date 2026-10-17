// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @dev Restricts all token flows to four tracked actors so conservation can be checked after every call.
contract PleaTokenHandler is Test {
    PleaToken private immutable token;
    address[4] private actors;

    constructor(PleaToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, fromBefore);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint8 fromSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 approved = token.allowance(from, spender);
        amount = bound(amount, 0, approved < fromBefore ? approved : fromBefore);

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        assertEq(token.allowance(from, spender), approved == type(uint256).max ? approved : approved - amount);
    }

    function attemptOverAllowance(uint8 fromSeed, uint8 spenderSeed, uint8 toSeed) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        uint256 approved = token.allowance(from, spender);
        if (approved == type(uint256).max) return;
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(from, to, approved + 1);
        assertEq(token.balanceOf(from), fromBefore);
        assertEq(token.balanceOf(to), toBefore);
        assertEq(token.allowance(from, spender), approved);
    }
}

contract PleaTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    PleaToken private token;
    address[4] private actors;

    function setUp() public {
        token = new PleaToken();
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        token.transfer(actors[0], SUPPLY);
        PleaTokenHandler handler = new PleaTokenHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.attemptOverAllowance.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyNeverChangesAndZeroAddressNeverHoldsTokens() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_AllTokensRemainAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
