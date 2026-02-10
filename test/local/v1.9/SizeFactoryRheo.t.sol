// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {VERSION} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {
    InitializeDataParamsRheo,
    InitializeFeeConfigParamsRheo,
    InitializeOracleParamsRheo,
    InitializeRiskConfigParamsRheo
} from "@src/factory/interfaces/RheoMarketTypes.sol";
import {Errors} from "@src/market/libraries/Errors.sol";

import {BaseTest} from "@test/BaseTest.sol";

contract SizeFactoryRheoTest is BaseTest {
    event RheoImplementationSet(address indexed oldRheoImplementation, address indexed newRheoImplementation);

    address internal owner;

    function setUp() public override {
        owner = makeAddr("owner");
        address _feeRecipient = makeAddr("feeRecipient");
        setupLocal(owner, _feeRecipient);
    }

    function _defaultRheoParams()
        internal
        view
        returns (
            InitializeFeeConfigParamsRheo memory fRheo,
            InitializeRiskConfigParamsRheo memory rRheo,
            InitializeOracleParamsRheo memory oRheo,
            InitializeDataParamsRheo memory dRheo
        )
    {
        uint256[] memory maturities = new uint256[](2);
        maturities[0] = block.timestamp + 30 days;
        maturities[1] = block.timestamp + 90 days;

        fRheo = InitializeFeeConfigParamsRheo({
            swapFeeAPR: 0,
            fragmentationFee: 0,
            liquidationRewardPercent: 0.05e18,
            overdueCollateralProtocolPercent: 0.1e18,
            collateralProtocolPercent: 0.1e18,
            feeRecipient: owner
        });

        rRheo = InitializeRiskConfigParamsRheo({
            crOpening: 1.5e18,
            crLiquidation: 1.3e18,
            minimumCreditBorrowToken: 5e6,
            minTenor: 1 hours,
            maxTenor: 365 days,
            maturities: maturities
        });

        oRheo = InitializeOracleParamsRheo({priceFeed: address(priceFeed)});

        dRheo = InitializeDataParamsRheo({
            weth: address(weth),
            underlyingCollateralToken: address(weth),
            underlyingBorrowToken: address(usdc),
            variablePool: address(variablePool),
            borrowTokenVault: d.borrowTokenVault,
            sizeFactory: address(sizeFactory)
        });
    }

    function test_SizeFactory_setRheoImplementation_revert_on_unauthorized() public {
        Rheo implementation = new Rheo();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(alice), 0x00)
        );
        sizeFactory.setRheoImplementation(address(implementation));
    }

    function test_SizeFactory_setRheoImplementation_revert_on_null_address() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.NULL_ADDRESS.selector));
        sizeFactory.setRheoImplementation(address(0));
    }

    function test_SizeFactory_setRheoImplementation_emits_event_and_updates_storage() public {
        Rheo implementation = new Rheo();

        assertEq(sizeFactory.rheoImplementation(), address(0));

        vm.expectEmit(address(sizeFactory));
        emit RheoImplementationSet(address(0), address(implementation));

        vm.prank(owner);
        sizeFactory.setRheoImplementation(address(implementation));

        assertEq(sizeFactory.rheoImplementation(), address(implementation));
    }

    function test_SizeFactory_createMarketRheo_revert_on_unauthorized() public {
        (
            InitializeFeeConfigParamsRheo memory fRheo,
            InitializeRiskConfigParamsRheo memory rRheo,
            InitializeOracleParamsRheo memory oRheo,
            InitializeDataParamsRheo memory dRheo
        ) = _defaultRheoParams();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(alice), 0x00)
        );
        sizeFactory.createMarketRheo(fRheo, rRheo, oRheo, dRheo);
    }

    function test_SizeFactory_createMarketRheo_revert_when_rheoImplementation_not_set() public {
        (
            InitializeFeeConfigParamsRheo memory fRheo,
            InitializeRiskConfigParamsRheo memory rRheo,
            InitializeOracleParamsRheo memory oRheo,
            InitializeDataParamsRheo memory dRheo
        ) = _defaultRheoParams();

        vm.prank(owner);
        vm.expectRevert();
        sizeFactory.createMarketRheo(fRheo, rRheo, oRheo, dRheo);
    }

    function test_SizeFactory_createMarketRheo_deploys_proxy_initializes_and_registers_market() public {
        Rheo implementation = new Rheo();
        vm.prank(owner);
        sizeFactory.setRheoImplementation(address(implementation));

        (
            InitializeFeeConfigParamsRheo memory fRheo,
            InitializeRiskConfigParamsRheo memory rRheo,
            InitializeOracleParamsRheo memory oRheo,
            InitializeDataParamsRheo memory dRheo
        ) = _defaultRheoParams();

        vm.prank(owner);
        address market = sizeFactory.createMarketRheo(fRheo, rRheo, oRheo, dRheo);

        assertTrue(market != address(0));
        assertGt(market.code.length, 0);
        assertTrue(sizeFactory.isMarket(market));
        assertEq(sizeFactory.getMarketsCount(), 2);

        // Validate the proxy was initialized with the params we provided.
        Rheo marketProxy = Rheo(payable(market));
        assertTrue(marketProxy.hasRole(0x00, owner));
        assertEq(marketProxy.version(), VERSION);

        assertEq(marketProxy.feeConfig().feeRecipient, owner);
        assertEq(marketProxy.feeConfig().liquidationRewardPercent, fRheo.liquidationRewardPercent);

        assertEq(marketProxy.riskConfig().minTenor, rRheo.minTenor);
        assertEq(marketProxy.riskConfig().maxTenor, rRheo.maxTenor);
        assertEq(marketProxy.riskConfig().maturities.length, rRheo.maturities.length);
        for (uint256 i = 0; i < rRheo.maturities.length; i++) {
            assertEq(marketProxy.riskConfig().maturities[i], rRheo.maturities[i]);
        }

        assertEq(marketProxy.oracle().priceFeed, oRheo.priceFeed);

        assertEq(marketProxy.data().nextDebtPositionId, 0);
        assertEq(marketProxy.data().nextCreditPositionId, type(uint256).max / 2);
        assertEq(address(marketProxy.data().underlyingCollateralToken), dRheo.underlyingCollateralToken);
        assertEq(address(marketProxy.data().underlyingBorrowToken), dRheo.underlyingBorrowToken);
        assertEq(address(marketProxy.data().borrowTokenVault), dRheo.borrowTokenVault);
    }
}
