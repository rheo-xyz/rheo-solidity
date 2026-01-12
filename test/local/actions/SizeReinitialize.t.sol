// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Errors} from "@src/market/libraries/Errors.sol";
import {BaseTest} from "@test/BaseTest.sol";

contract SizeReinitializeTest is BaseTest {
    address admin;
    uint256 private constant OVERDUE_LIQUIDATION_REWARD_PERCENT = 0.01e18;
    uint256 private constant OVERDUE_COLLATERAL_PROTOCOL_PERCENT = 0.001e18;

    function setUp() public override {
        super.setUp();
        admin = address(this); // The owner/admin from BaseTest setup
    }

    function test_Size_reinitialize_success() public {
        // Only DEFAULT_ADMIN_ROLE can call reinitialize
        vm.prank(admin);
        size.reinitialize(OVERDUE_LIQUIDATION_REWARD_PERCENT, OVERDUE_COLLATERAL_PROTOCOL_PERCENT);

        assertEq(_overdueLiquidationRewardPercent(), OVERDUE_LIQUIDATION_REWARD_PERCENT);
        assertEq(size.feeConfig().overdueCollateralProtocolPercent, OVERDUE_COLLATERAL_PROTOCOL_PERCENT);
    }

    function test_Size_reinitialize_reverts_unauthorized() public {
        // Should revert when called by non-admin
        vm.prank(alice);
        vm.expectRevert();
        size.reinitialize(OVERDUE_LIQUIDATION_REWARD_PERCENT, OVERDUE_COLLATERAL_PROTOCOL_PERCENT);
    }

    function test_Size_reinitialize_multiple_calls() public {
        // First call should succeed
        vm.prank(admin);
        size.reinitialize(OVERDUE_LIQUIDATION_REWARD_PERCENT, OVERDUE_COLLATERAL_PROTOCOL_PERCENT);

        // Second call should fail (already initialized to version 1.08.03)
        vm.prank(admin);
        vm.expectRevert();
        size.reinitialize(OVERDUE_LIQUIDATION_REWARD_PERCENT, OVERDUE_COLLATERAL_PROTOCOL_PERCENT);
    }

}
