// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Contract, Networks} from "@script/Networks.sol";
import {ProposeSafeTxUpgradeToV1_8_2Script} from "@script/ProposeSafeTxUpgradeToV1_8_2.s.sol";
import {ForkTest} from "@test/fork/ForkTest.sol";
import {console} from "forge-std/console.sol";

import {SizeFactory} from "@src/factory/SizeFactory.sol";

import {Errors} from "@src/market/libraries/Errors.sol";
import {SellCreditMarketParams} from "@src/market/libraries/actions/SellCreditMarket.sol";
import {UpdateConfigParams} from "@src/market/libraries/actions/UpdateConfig.sol";
import {SizeMock} from "@test/mocks/SizeMock.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {RESERVED_ID} from "@src/market/libraries/LoanLibrary.sol";
import {YieldCurveHelper} from "@test/helpers/libraries/YieldCurveHelper.sol";

contract ForkDebtTokenCapTest is ForkTest, Networks {
    function setUp() public override(ForkTest) {
        vm.createSelectFork("base_archive");
        // 2025-12-22 18h45 UTC
        vm.rollFork(39819900);

        sizeFactory = SizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);
        size = SizeMock(address(getUnpausedMarkets(sizeFactory)[3]));
        assertEq(size.data().underlyingCollateralToken.symbol(), "VIRTUAL");
        assertEq(size.data().underlyingBorrowToken.symbol(), "USDC");

        _upgradeToV1_8_2();
    }

    function testFork_ForkDebtTokenCap_debtTokenCap_exceeded() public {
        assertEq(size.extSload(bytes32(uint256(29))), bytes32(uint256(type(uint256).max)));

        vm.prank(contracts[block.chainid][Contract.SIZE_GOVERNANCE]);
        size.updateConfig(UpdateConfigParams({key: "debtTokenCap", value: 700e6}));

        assertEq(size.extSload(bytes32(uint256(29))), bytes32(uint256(700e6)));
        assertEqApprox(size.data().debtToken.totalSupply(), 677e6, 1e6);

        _deposit(alice, size.data().underlyingCollateralToken, 1000e18);

        _deposit(bob, size.data().underlyingBorrowToken, 100e6);
        _buyCreditLimit(bob, block.timestamp + 365 days, YieldCurveHelper.pointCurve(365 days, 0.1e18));

        vm.prank(alice);
        try size.sellCreditMarket(
            SellCreditMarketParams({
                lender: bob,
                creditPositionId: RESERVED_ID,
                amount: 100e6,
                tenor: 365 days,
                maxAPR: type(uint256).max,
                deadline: block.timestamp + 365 days,
                exactAmountIn: true,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        ) {
            assertTrue(false, "Expected revert");
        } catch (bytes memory err) {
            assertEq(bytes4(err), Errors.DEBT_TOKEN_CAP_EXCEEDED.selector);
        }
    }

    function _upgradeToV1_8_2() public {
        ProposeSafeTxUpgradeToV1_8_2Script script = new ProposeSafeTxUpgradeToV1_8_2Script();
        (address[] memory targets, bytes[] memory datas) = script.getUpgradeToV1_8_2Data();
        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(contracts[block.chainid][Contract.SIZE_GOVERNANCE]);
            Address.functionCall(targets[i], datas[i]);
        }
    }
}
