// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @dev Restricts all token flows to four tracked actors so conservation can be checked after every call.
contract PleaTokenHandler is Test {
    PleaToken private immutable token;
    address[4] private actors;

    // This ledger is initialized from the fixture's allocation and updated only
    // from successful action inputs, never copied back from the token's getters.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(PleaToken token_, address[4] memory actors_, uint256 initialAllocation) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = initialAllocation;
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    /// @dev Keep revocation, spendable finite approvals and infinite approvals
    /// common enough to interleave with transfers; approve() also tests raw uint256s.
    function approveBoundary(uint8 ownerSeed, uint8 spenderSeed, uint8 mode, uint256 amount) external {
        if (mode % 3 == 0) amount = 0;
        else if (mode % 3 == 1) amount = bound(amount, 0, expectedBalance[actors[ownerSeed % 4]]);
        else amount = type(uint256).max;
        approve(ownerSeed, spenderSeed, amount);
    }

    function transferFrom(uint8 fromSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 approved = expectedAllowance[from][spender];
        uint256 held = expectedBalance[from];
        amount = bound(amount, 0, approved < held ? approved : held);

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) expectedAllowance[from][spender] -= amount;
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        assertEq(token.allowance(from, spender), approved == type(uint256).max ? approved : approved - amount);
    }

    function attemptOverAllowance(uint8 fromSeed, uint8 spenderSeed, uint8 toSeed) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        uint256 approved = expectedAllowance[from][spender];
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

    function attemptOverBalance(uint8 fromSeed, uint8 toSeed, uint256 excess) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 held = expectedBalance[from];
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    /// @dev Both rejection stages must preserve the entire allowance matrix.
    /// Infinite/large approvals reach the balance check; small ones fail authorization.
    function attemptTransferFromOverBalance(uint8 fromSeed, uint8 spenderSeed, uint8 toSeed) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 held = expectedBalance[from];
        uint256 approved = expectedAllowance[from][spender];
        uint256 amount = held + 1;
        bytes memory reason = approved < amount
            ? abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
            : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount);
        vm.expectRevert(reason);
        vm.prank(spender);
        token.transferFrom(from, actors[toSeed % 4], amount);
    }

    function attemptInvalidReceiver(uint8 fromSeed, uint8 spenderSeed, uint256 amount, bool delegated) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 limit = expectedBalance[from];
        if (delegated && expectedAllowance[from][spender] < limit) limit = expectedAllowance[from][spender];
        amount = bound(amount, 0, limit);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : from);
        if (delegated) token.transferFrom(from, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function attemptInvalidApproval(uint8 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[ownerSeed % 4]);
        token.approve(address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PleaTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    PleaToken private token;
    address[4] private actors;
    PleaTokenHandler private handler;

    function setUp() public {
        token = new PleaToken();
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        token.transfer(actors[0], SUPPLY);
        handler = new PleaTokenHandler(token, actors, SUPPLY);

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.attemptOverAllowance.selector;
        selectors[4] = handler.approveBoundary.selector;
        selectors[5] = handler.attemptOverBalance.selector;
        selectors[6] = handler.attemptTransferFromOverBalance.selector;
        selectors[7] = handler.attemptInvalidReceiver.selector;
        selectors[8] = handler.attemptInvalidApproval.selector;
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
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_EveryBalanceAndAllowanceMatchesTheActionLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            address owner = actors[i];
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner), "unexpected holder balance");
            assertEq(token.allowance(owner, address(0)), 0, "zero spender gained approval");
            assertEq(token.allowance(address(0), owner), 0, "zero owner gained approval");
            for (uint256 j; j < actors.length; ++j) {
                address spender = actors[j];
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "unexpected allowance change"
                );
            }
        }
    }
}
