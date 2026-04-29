// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAToken} from "@aave/interfaces/IAToken.sol";
import {UserView} from "@src/market/SizeView.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {Errors} from "@src/market/libraries/Errors.sol";

import {SetVaultOnBehalfOfParams, SetVaultParams} from "@src/market/libraries/actions/SetVault.sol";

import {Action, Authorization} from "@src/factory/libraries/Authorization.sol";

import {ERC4626_ADAPTER_ID} from "@src/market/token/NonTransferrableRebasingTokenVault.sol";
import {BaseTest} from "@test/BaseTest.sol";

contract AuthorizationSetVaultTest is BaseTest {
    function setUp() public override {
        super.setUp();
        _setVaultAdapter(vaultSolady, ERC4626_ADAPTER_ID);
    }

    function test_AuthorizationSetVault_setVaultOnBehalfOf() public {
        _setAuthorization(alice, candy, Authorization.getActionsBitmap(Action.SET_VAULT));

        assertEq(size.data().borrowTokenVault.vaultOf(alice), address(0));

        vm.prank(candy);
        size.setVaultOnBehalfOf(
            SetVaultOnBehalfOfParams({
                params: SetVaultParams({vault: address(vaultSolady), forfeitOldShares: false}),
                onBehalfOf: alice
            })
        );

        assertEq(size.data().borrowTokenVault.vaultOf(alice), address(vaultSolady));
    }

    function test_AuthorizationSetVault_validation() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.UNAUTHORIZED_ACTION.selector, alice, bob, Action.SET_VAULT));
        vm.prank(alice);
        size.setVaultOnBehalfOf(
            SetVaultOnBehalfOfParams({
                params: SetVaultParams({vault: address(vaultSolady), forfeitOldShares: false}),
                onBehalfOf: bob
            })
        );
    }

    // Cantina #82: forfeit zeroes user shares irrecoverably; an authorized operator must not be
    // able to trigger it on the principal's behalf, even with Action.SET_VAULT granted.
    function test_AuthorizationSetVault_setVaultOnBehalfOf_forfeitOldShares_revertsForOperator() public {
        _setAuthorization(alice, candy, Authorization.getActionsBitmap(Action.SET_VAULT));

        vm.expectRevert(abi.encodeWithSelector(Errors.UNAUTHORIZED_ACTION.selector, candy, alice, Action.SET_VAULT));
        vm.prank(candy);
        size.setVaultOnBehalfOf(
            SetVaultOnBehalfOfParams({
                params: SetVaultParams({vault: address(vaultSolady), forfeitOldShares: true}),
                onBehalfOf: alice
            })
        );
    }

    // Sanity check: the safe migration path (forfeitOldShares == false) is still callable by an
    // authorized operator after the Cantina #82 fix.
    function test_AuthorizationSetVault_setVaultOnBehalfOf_safeMigration_succeedsForOperator() public {
        _setAuthorization(alice, candy, Authorization.getActionsBitmap(Action.SET_VAULT));

        assertEq(size.data().borrowTokenVault.vaultOf(alice), address(0));

        vm.prank(candy);
        size.setVaultOnBehalfOf(
            SetVaultOnBehalfOfParams({
                params: SetVaultParams({vault: address(vaultSolady), forfeitOldShares: false}),
                onBehalfOf: alice
            })
        );

        assertEq(size.data().borrowTokenVault.vaultOf(alice), address(vaultSolady));
    }

    // The principal must retain the emergency-escape path: a self-call with forfeitOldShares=true
    // continues to succeed so a user can move off a compromised vault without an operator.
    function test_AuthorizationSetVault_setVault_forfeitOldShares_succeedsForPrincipal() public {
        assertEq(size.data().borrowTokenVault.vaultOf(alice), address(0));

        vm.prank(alice);
        size.setVault(SetVaultParams({vault: address(vaultSolady), forfeitOldShares: true}));

        assertEq(size.data().borrowTokenVault.vaultOf(alice), address(vaultSolady));
    }
}
