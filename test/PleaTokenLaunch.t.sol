// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @dev Local test fixture only; it is not a launch or application contract.
contract PleaFactoryHarness {
    function deploy() external returns (PleaToken) {
        return new PleaToken();
    }

    function deployCreate2(bytes32 salt) external returns (PleaToken) {
        return new PleaToken{salt: salt}();
    }

    function move(PleaToken token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

contract PleaTokenLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    PleaFactoryHarness private factory;
    address private requester;

    function setUp() public {
        factory = new PleaFactoryHarness();
        requester = makeAddr("requester");
    }

    function test_FactoryReceivesEntireSupplyInsteadOfTransactionOrigin() public {
        vm.prank(requester, requester);
        PleaToken token = factory.deploy();
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(requester), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function testFuzz_Create2DeploysWithNoArgumentsOrExternalDependencies(bytes32 salt) public {
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(PleaToken).creationCode))
                    )
                )
            )
        );
        vm.prank(requester, requester);
        PleaToken token = factory.deployCreate2(salt);
        assertEq(address(token), predicted);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(requester), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LaunchAllocationClaimAndPoolTransfersArriveWhole() public {
        // These addresses model transfer counterparties, not the real pool or distributor implementations.
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");
        PleaToken token = factory.deploy();
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY / 10;
        uint256 remainder = SUPPLY - swarmShare - poolShare;

        assertTrue(factory.move(token, distributor, swarmShare));
        assertTrue(factory.move(token, poolManager, poolShare));
        assertTrue(factory.move(token, requester, remainder));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarmShare);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.balanceOf(requester), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarmShare));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarmShare);

        uint256 traded = 100 ether;
        vm.prank(poolManager);
        assertTrue(token.transfer(trader, traded));
        assertEq(token.balanceOf(trader), traded);
        assertEq(token.balanceOf(poolManager), poolShare - traded);
        vm.prank(trader);
        assertTrue(token.transfer(poolManager, traded));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
