// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {Contract, NetworkConfiguration, Networks} from "@script/Networks.sol";

import {SizeFactory} from "@src/factory/SizeFactory.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

import {DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {BuyCreditLimitParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditLimit.sol";
import {SellCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";
import {RepayParams} from "@rheo-fm/src/market/libraries/actions/Repay.sol";

import {DebtPosition, RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";

contract RheoCompat is Rheo {
    // Base mainnet CollectionsManager (at least as of 2026-02-10) uses legacy helpers to null-check offers.
    // Rheo FM markets expose `isUserDefinedLimitOrdersNull`, so we provide compatibility shims.
    function isUserDefinedLoanOfferNull(address user) external view returns (bool) {
        return state.data.users[user].loanOffer.maturities.length == 0 && state.data.users[user].loanOffer.aprs.length == 0;
    }

    function isUserDefinedBorrowOfferNull(address user) external view returns (bool) {
        return state.data.users[user].borrowOffer.maturities.length == 0 && state.data.users[user].borrowOffer.aprs.length == 0;
    }
}

contract ForkCreateMarketRheoTest is Test, Networks {
    uint256 internal constant FORK_BLOCK = 41_946_442; // 2026-02-10 00:10:31 UTC

    address internal constant PRICE_FEED_WETH_USDC = 0xd6938E55cc5f4B553948Cc153d360E8a8FA0de72;
    address internal constant BORROW_TOKEN_VAULT_USDC = 0x0447430C327cCE6C0c43Ec0eb0271fecdAD471b2;

    uint256 internal constant MATURITY_2026_03_01 = 1_772_323_200;
    uint256 internal constant MATURITY_2026_04_01 = 1_775_001_600;
    uint256 internal constant MATURITY_2026_05_01 = 1_777_593_600;
    uint256 internal constant MATURITY_2026_06_01 = 1_780_272_000;
    uint256 internal constant MATURITY_2026_07_01 = 1_782_864_000;
    uint256 internal constant MATURITY_2026_08_01 = 1_785_542_400;

    SizeFactory internal factory;
    address internal factoryOwner;

    IERC20Metadata internal weth;
    IERC20Metadata internal usdc;
    address internal lender = address(0x10000);
    address internal borrower = address(0x20000);

    function setUp() public {
        vm.createSelectFork("base_archive", FORK_BLOCK);

        factory = SizeFactory(contracts[BASE_MAINNET][Contract.SIZE_FACTORY]);
        factoryOwner = contracts[BASE_MAINNET][Contract.SIZE_GOVERNANCE];

        NetworkConfiguration memory cfg = params("base-production-weth-usdc");
        weth = IERC20Metadata(cfg.underlyingCollateralToken);
        usdc = IERC20Metadata(cfg.underlyingBorrowToken);

        vm.label(address(factory), "SizeFactory");
        vm.label(factoryOwner, "SizeFactoryOwner");
        vm.label(address(weth), "WETH");
        vm.label(address(usdc), "USDC");
        vm.label(lender, "lender");
        vm.label(borrower, "borrower");
    }

    function testFork_CreateMarketRheo_buyCreditLimit_sellCreditMarket_repay() public {
        // Upgrade the on-chain SizeFactory proxy to the local implementation on this branch (v1.9).
        SizeFactory newFactoryImplementation = new SizeFactory();
        vm.prank(factoryOwner);
        factory.upgradeToAndCall(address(newFactoryImplementation), "");

        // Configure the Rheo FM implementation used for new markets.
        RheoCompat rheoImplementation = new RheoCompat();
        vm.prank(factoryOwner);
        factory.setRheoImplementation(address(rheoImplementation));

        uint256[] memory maturities = new uint256[](6);
        maturities[0] = MATURITY_2026_03_01;
        maturities[1] = MATURITY_2026_04_01;
        maturities[2] = MATURITY_2026_05_01;
        maturities[3] = MATURITY_2026_06_01;
        maturities[4] = MATURITY_2026_07_01;
        maturities[5] = MATURITY_2026_08_01;

        uint256[] memory aprs = new uint256[](6);
        aprs[0] = 0.1e18;
        aprs[1] = 0.1e18;
        aprs[2] = 0.1e18;
        aprs[3] = 0.1e18;
        aprs[4] = 0.1e18;
        aprs[5] = 0.1e18;

        InitializeFeeConfigParams memory feeConfig = InitializeFeeConfigParams({
            swapFeeAPR: 0,
            fragmentationFee: 0,
            liquidationRewardPercent: 0.05e18,
            overdueCollateralProtocolPercent: 0.1e18,
            collateralProtocolPercent: 0.1e18,
            feeRecipient: factoryOwner
        });

        InitializeRiskConfigParams memory riskConfig = InitializeRiskConfigParams({
            crOpening: 1.5e18,
            crLiquidation: 1.3e18,
            minimumCreditBorrowToken: 10e6,
            minTenor: 1 days,
            maxTenor: 365 days,
            maturities: maturities
        });

        InitializeOracleParams memory oracleParams = InitializeOracleParams({priceFeed: PRICE_FEED_WETH_USDC});

        NetworkConfiguration memory cfg = params("base-production-weth-usdc");
        InitializeDataParams memory dataParams = InitializeDataParams({
            weth: cfg.weth,
            underlyingCollateralToken: cfg.underlyingCollateralToken,
            underlyingBorrowToken: cfg.underlyingBorrowToken,
            variablePool: cfg.variablePool,
            borrowTokenVault: BORROW_TOKEN_VAULT_USDC,
            sizeFactory: address(factory)
        });

        vm.prank(factoryOwner);
        address marketAddr = factory.createMarketRheo(feeConfig, riskConfig, oracleParams, dataParams);
        IRheo market = IRheo(payable(marketAddr));

        assertTrue(factory.isMarket(marketAddr));
        assertEq(market.version(), "v1.9");

        // Lender: deposit USDC to mint borrowTokenVault shares, then create a fixed-maturity loan offer.
        uint256 lenderDepositAmount = 1_000e6;
        deal(address(usdc), lender, lenderDepositAmount);
        vm.startPrank(lender);
        usdc.approve(address(market), lenderDepositAmount);
        market.deposit(DepositParams({token: address(usdc), amount: lenderDepositAmount, to: lender}));
        market.buyCreditLimit(BuyCreditLimitParams({maturities: maturities, aprs: aprs}));
        vm.stopPrank();

        // Borrower: deposit collateral, then borrow from the lender's loan offer.
        uint256 borrowerCollateralAmount = 5e18;
        deal(address(weth), borrower, borrowerCollateralAmount);
        vm.startPrank(borrower);
        weth.approve(address(market), borrowerCollateralAmount);
        market.deposit(DepositParams({token: address(weth), amount: borrowerCollateralAmount, to: borrower}));

        uint256 maturity = MATURITY_2026_03_01;
        uint256 cashAmountOut = 100e6;
        market.sellCreditMarket(
            SellCreditMarketParams({
                lender: lender,
                creditPositionId: RESERVED_ID,
                amount: cashAmountOut,
                maturity: maturity,
                deadline: block.timestamp + 1 hours,
                maxAPR: 0.2e18,
                exactAmountIn: false,
                collectionId: RESERVED_ID,
                rateProvider: address(0)
            })
        );
        vm.stopPrank();

        // New market: first debt position id is 0.
        DebtPosition memory debtBefore = market.getDebtPosition(0);
        assertEq(debtBefore.borrower, borrower);
        assertGt(debtBefore.futureValue, cashAmountOut);
        assertEq(debtBefore.dueDate, maturity);
        assertEq(debtBefore.liquidityIndexAtRepayment, 0);

        // Borrower received `cashAmountOut` in borrowTokenVault shares, but owes the (larger) `futureValue`.
        // Top up enough shares so repay can succeed.
        uint256 repayAmount = debtBefore.futureValue;
        if (repayAmount > cashAmountOut) {
            uint256 topUp = repayAmount - cashAmountOut + 2; // +2 buffer for potential rounding in the vault.
            deal(address(usdc), borrower, topUp);
            vm.startPrank(borrower);
            usdc.approve(address(market), topUp);
            market.deposit(DepositParams({token: address(usdc), amount: topUp, to: borrower}));
            vm.stopPrank();
        }

        // Repay (full).
        vm.prank(borrower);
        market.repay(RepayParams({debtPositionId: 0, borrower: borrower}));

        DebtPosition memory debtAfter = market.getDebtPosition(0);
        assertEq(debtAfter.borrower, borrower);
        assertEq(debtAfter.futureValue, 0);
        assertEq(debtAfter.dueDate, maturity);
        assertGt(debtAfter.liquidityIndexAtRepayment, 0);
    }
}
