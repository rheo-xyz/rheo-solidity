// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {GetMarketShutdownCalldataScript} from "@script/GetMarketShutdownCalldata.s.sol";
import {Contract, Networks} from "@script/Networks.sol";
import {ProposeSafeTxUpgradeToV1_9_part_1_Script} from "@script/ProposeSafeTxUpgradeToV1_9_part_1.s.sol";
import {ProposeSafeTxUpgradeToV1_9_part_2_Script} from "@script/ProposeSafeTxUpgradeToV1_9_part_2.s.sol";

import {SizeFactory} from "@src/factory/SizeFactory.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {VERSION as RHEO_VERSION} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {BuyCreditLimitParams} from "@rheo-fm/src/market/libraries/actions/BuyCreditLimit.sol";
import {DepositParams} from "@rheo-fm/src/market/libraries/actions/Deposit.sol";
import {RepayParams} from "@rheo-fm/src/market/libraries/actions/Repay.sol";
import {SellCreditMarketParams} from "@rheo-fm/src/market/libraries/actions/SellCreditMarket.sol";

import {DebtPosition, RESERVED_ID} from "@rheo-fm/src/market/libraries/LoanLibrary.sol";

abstract contract ForkUpgradeToV1_9Base is Test, Networks {
    uint256 internal constant RHEO_OVERDUE_LIQUIDATION_REWARD_SLOT = 29;
    uint256 internal constant OVERDUE_LIQUIDATION_REWARD_PERCENT = 0.01e18;

    address internal factoryOwner;
    SizeFactory internal factory;

    address internal lender = address(0x10000);
    address internal borrower = address(0x20000);

    function _fork(string memory rpcAlias, uint256 blockNumber) internal {
        vm.createSelectFork(rpcAlias, blockNumber);
        factory = SizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);
        factoryOwner = contracts[block.chainid][Contract.SIZE_GOVERNANCE];

        vm.label(address(factory), "SizeFactory");
        vm.label(factoryOwner, "FactoryOwner");
        vm.label(lender, "lender");
        vm.label(borrower, "borrower");
    }

    function _fundGovernanceForFullShutdown(ISize[] memory legacyMarkets) internal {
        // Compute required borrow token liquidity (sum of futureValues) per underlying borrow token.
        GetMarketShutdownCalldataScript shutdownScript = new GetMarketShutdownCalldataScript();

        address[] memory tokens = new address[](legacyMarkets.length);
        uint256[] memory totals = new uint256[](legacyMarkets.length);
        uint256 n = 0;

        for (uint256 i = 0; i < legacyMarkets.length; i++) {
            ISize m = legacyMarkets[i];
            shutdownScript.collectPositions(m);
            uint256 need = shutdownScript.getSumFutureValue(m);
            address token = address(m.data().underlyingBorrowToken);

            uint256 idx = type(uint256).max;
            for (uint256 j = 0; j < n; j++) {
                if (tokens[j] == token) {
                    idx = j;
                    break;
                }
            }
            if (idx == type(uint256).max) {
                idx = n++;
                tokens[idx] = token;
            }
            totals[idx] += need;
        }

        for (uint256 i = 0; i < n; i++) {
            if (totals[i] > 0) {
                // 2x buffer to cover rounding/index differences across vault operations.
                deal(tokens[i], factoryOwner, totals[i] * 2 + 1);
            }
        }
    }

    function _execAsOwner(address[] memory targets, bytes[] memory datas) internal {
        require(targets.length == datas.length, "length mismatch");
        vm.startPrank(factoryOwner);
        for (uint256 i = 0; i < targets.length; i++) {
            (bool ok, bytes memory ret) = targets[i].call(datas[i]);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(ret, 0x20), mload(ret))
                }
            }
        }
        vm.stopPrank();
    }

    function _findRheoMarketWethUsdc() internal view returns (IRheo) {
        address weth = contracts[block.chainid][Contract.WETH];
        address[] memory markets = factory.getMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            if (!factory.isRheoMarket(markets[i])) {
                continue;
            }
            IRheo m = IRheo(payable(markets[i]));
            if (address(m.data().underlyingCollateralToken) == weth) {
                // WETH/USDC market on all supported networks borrows USDC.
                return m;
            }
        }
        revert("WETH/* market not found");
    }

    function _overdueLiquidationRewardPercent(IRheo market) internal view returns (uint256) {
        return uint256(market.extSload(bytes32(RHEO_OVERDUE_LIQUIDATION_REWARD_SLOT)));
    }

    function _assertOverdueLiquidationRewardSetForUnpausedMarkets() internal view {
        address[] memory markets = factory.getMarkets();
        uint256 unpausedMarketsCount = 0;
        for (uint256 i = 0; i < markets.length; i++) {
            if (PausableUpgradeable(markets[i]).paused()) {
                continue;
            }
            unpausedMarketsCount++;
            assertTrue(factory.isRheoMarket(markets[i]));
            assertEq(_overdueLiquidationRewardPercent(IRheo(payable(markets[i]))), OVERDUE_LIQUIDATION_REWARD_PERCENT);
        }
        assertGt(unpausedMarketsCount, 0);
    }

    function _assertMigrationEffects(ISize[] memory legacyMarkets) internal view {
        // Legacy markets should be paused and removed from the factory registry.
        for (uint256 i = 0; i < legacyMarkets.length; i++) {
            assertTrue(PausableUpgradeable(address(legacyMarkets[i])).paused());
            assertFalse(factory.isMarket(address(legacyMarkets[i])));
        }

        // New markets should replace the legacy set 1:1.
        assertEq(factory.getMarketsCount(), legacyMarkets.length);
    }

    function _smokeRheoMarket(IRheo market, uint256[] memory maturities) internal {
        assertEq(market.version(), RHEO_VERSION);

        IERC20Metadata coll = market.data().underlyingCollateralToken;
        IERC20Metadata borrowTok = market.data().underlyingBorrowToken;

        uint256[] memory aprs = new uint256[](maturities.length);
        for (uint256 i = 0; i < aprs.length; i++) {
            aprs[i] = 0.1e18;
        }

        // Lender: deposit borrow token, then create a fixed-maturity loan offer.
        uint256 lenderDepositAmount = 10_000 * (10 ** borrowTok.decimals());
        deal(address(borrowTok), lender, lenderDepositAmount);
        vm.startPrank(lender);
        borrowTok.approve(address(market), lenderDepositAmount);
        market.deposit(DepositParams({token: address(borrowTok), amount: lenderDepositAmount, to: lender}));
        market.buyCreditLimit(BuyCreditLimitParams({maturities: maturities, aprs: aprs}));
        vm.stopPrank();

        // Borrower: deposit collateral, then borrow against the lender's offer.
        uint256 borrowerCollateralAmount = 10 ether;
        deal(address(coll), borrower, borrowerCollateralAmount);
        vm.startPrank(borrower);
        coll.approve(address(market), borrowerCollateralAmount);
        market.deposit(DepositParams({token: address(coll), amount: borrowerCollateralAmount, to: borrower}));

        uint256 maturity = maturities[0];
        uint256 cashAmountOut = 100 * (10 ** borrowTok.decimals());
        uint256 minimumCreditBorrowToken = market.riskConfig().minimumCreditBorrowToken;
        if (cashAmountOut < minimumCreditBorrowToken) {
            cashAmountOut = minimumCreditBorrowToken + 1;
        }
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

        // Repay the first debt position id (starts at 0 in Rheo FM).
        DebtPosition memory debtBefore = market.getDebtPosition(0);
        assertEq(debtBefore.borrower, borrower);
        assertEq(debtBefore.dueDate, maturity);
        assertGt(debtBefore.futureValue, cashAmountOut);

        uint256 repayAmount = debtBefore.futureValue;
        if (repayAmount > cashAmountOut) {
            uint256 topUp = repayAmount - cashAmountOut + 10;
            deal(address(borrowTok), borrower, topUp);
            vm.startPrank(borrower);
            borrowTok.approve(address(market), topUp);
            market.deposit(DepositParams({token: address(borrowTok), amount: topUp, to: borrower}));
            vm.stopPrank();
        }

        vm.prank(borrower);
        market.repay(RepayParams({debtPositionId: 0, borrower: borrower}));

        DebtPosition memory debtAfter = market.getDebtPosition(0);
        assertEq(debtAfter.futureValue, 0);
        assertGt(debtAfter.liquidityIndexAtRepayment, 0);
    }

    function _assertPart1Effects(ISize[] memory legacyMarkets) internal view {
        // After part 1, legacy markets should be paused and removed from the factory registry.
        for (uint256 i = 0; i < legacyMarkets.length; i++) {
            assertTrue(PausableUpgradeable(address(legacyMarkets[i])).paused());
            assertFalse(factory.isMarket(address(legacyMarkets[i])));
        }
    }

    function _runForkMigrationAndSmoke() internal {
        ISize[] memory legacyMarkets = getUnpausedSizeMarkets(factory);
        _fundGovernanceForFullShutdown(legacyMarkets);

        ProposeSafeTxUpgradeToV1_9_part_1_Script scriptPart1 = new ProposeSafeTxUpgradeToV1_9_part_1_Script();
        (address[] memory migrationTargetsPart1, bytes[] memory migrationDatasPart1) =
            scriptPart1.getUpgradeToV1_9Part1Data();
        _execAsOwner(migrationTargetsPart1, migrationDatasPart1);
        _assertPart1Effects(legacyMarkets);

        ProposeSafeTxUpgradeToV1_9_part_2_Script scriptPart2 = new ProposeSafeTxUpgradeToV1_9_part_2_Script();
        (address[] memory migrationTargetsPart2, bytes[] memory migrationDatasPart2) =
            scriptPart2.getUpgradeToV1_9Part2Data();
        _execAsOwner(migrationTargetsPart2, migrationDatasPart2);

        _assertMigrationEffects(legacyMarkets);
        _assertOverdueLiquidationRewardSetForUnpausedMarkets();

        IRheo wethMarket = _findRheoMarketWethUsdc();
        _smokeRheoMarket(wethMarket, scriptPart1.v1_9Maturities());
    }
}

contract ForkUpgradeToV1_9BaseMainnetTest is ForkUpgradeToV1_9Base {
    uint256 internal constant FORK_BLOCK = 41_975_096;
    // 2026-02-10 16:05:39 UTC

    function setUp() public {
        string memory alchemyKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        if (bytes(alchemyKey).length == 0) {
            vm.skip(true);
        }
        _fork("base", FORK_BLOCK);
    }

    function testFork_UpgradeToV1_9_baseMainnet_migrates_and_smokes() public {
        _runForkMigrationAndSmoke();
    }
}

contract ForkUpgradeToV1_9EthereumMainnetTest is ForkUpgradeToV1_9Base {
    uint256 internal constant FORK_BLOCK = 24_427_455;
    // 2026-02-10 16:05:35 UTC

    function setUp() public {
        string memory alchemyKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        if (bytes(alchemyKey).length == 0) {
            vm.skip(true);
        }
        _fork("mainnet", FORK_BLOCK);
    }

    function testFork_UpgradeToV1_9_ethereumMainnet_migrates_and_smokes() public {
        _runForkMigrationAndSmoke();
    }
}

contract ForkUpgradeToV1_9BaseSepoliaTest is ForkUpgradeToV1_9Base {
    uint256 internal constant FORK_BLOCK = 37_487_867;
    // 2026-02-10 17:20:22 UTC

    function setUp() public {
        string memory alchemyKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        if (bytes(alchemyKey).length == 0) {
            vm.skip(true);
        }
        _fork("base_sepolia", FORK_BLOCK);
    }

    function testFork_UpgradeToV1_9_baseSepolia_migrates_and_smokes() public {
        _runForkMigrationAndSmoke();
    }
}
