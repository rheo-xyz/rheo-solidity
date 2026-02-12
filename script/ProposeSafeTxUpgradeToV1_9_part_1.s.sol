// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {BaseScript} from "@script/BaseScript.sol";
import {GetMarketShutdownCalldataScript} from "@script/GetMarketShutdownCalldata.s.sol";
import {Contract, Networks} from "@script/Networks.sol";

import {SizeFactory} from "@src/factory/SizeFactory.sol";
import {ISizeFactory} from "@src/factory/interfaces/ISizeFactory.sol";
import {Size} from "@src/market/Size.sol";

import {IMulticall} from "@src/market/interfaces/IMulticall.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {ISizeAdmin} from "@src/market/interfaces/ISizeAdmin.sol";

import {DepositParams} from "@src/market/libraries/actions/Deposit.sol";

import {
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@src/market/libraries/actions/Initialize.sol";
import {MarketShutdownParams} from "@src/market/libraries/actions/MarketShutdown.sol";
import {WithdrawParams} from "@src/market/libraries/actions/Withdraw.sol";

import {
    InitializeDataParams as InitializeDataParamsRheo,
    InitializeFeeConfigParams as InitializeFeeConfigParamsRheo,
    InitializeOracleParams as InitializeOracleParamsRheo,
    InitializeRiskConfigParams as InitializeRiskConfigParamsRheo
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {console} from "forge-std/console.sol";

import {Safe} from "@safe-utils/Safe.sol";

import {CollectionsManager as RheoCollectionsManager} from "@rheo-fm/src/collections/CollectionsManager.sol";
import {ICollectionsManager as ICollectionsManagerRheo} from
    "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";

contract ProposeSafeTxUpgradeToV1_9_part_1_Script is BaseScript, Networks {
    using Safe for *;

    struct UpgradeCtx {
        SizeFactory sizeFactory;
        address owner;
        ISize[] legacyMarkets;
        address newSizeFactoryImplementation;
        address newSizeImplementation;
        address newRheoImplementation;
        address newCollectionsManagerProxy;
        address[] groupBorrowTokens;
        ISize[] anchors;
        uint256 groups;
        uint256 depositGroups;
        uint256[] groupRequiredBorrowTokenLiquidity;
        uint256[] maturities;
        bool needsLegacySizeUpgrade;
    }

    address signer;
    string derivationPath;
    bool isTestnet;

    modifier parseEnv() {
        // Testnets use an EOA admin flow (no multisig), mainnets use Safe proposals.
        isTestnet = _isTestnet(block.chainid);

        if (!isTestnet) {
            safe.initialize(contracts[block.chainid][Contract.SIZE_GOVERNANCE]);
            signer = vm.envAddress("SIGNER");
            derivationPath = vm.envString("LEDGER_PATH");
        }

        _;
    }

    function run() public parseEnv {
        console.log("ProposeSafeTxUpgradeToV1_9_part_1_Script");

        // Broadcast is only used to deploy the new implementations and the new CollectionsManager proxy.
        vm.startBroadcast();
        (address[] memory targets, bytes[] memory datas) = getUpgradeToV1_9Part1Data();

        if (isTestnet) {
            // Execute the calls directly (EOA admin flow).
            _execute(targets, datas);
            vm.stopBroadcast();
        } else {
            vm.stopBroadcast();
            safe.proposeTransactions(targets, datas, signer, derivationPath);
        }

        console.log("ProposeSafeTxUpgradeToV1_9_part_1_Script: done");
    }

    function getUpgradeToV1_9Part1Data() public returns (address[] memory targets, bytes[] memory datas) {
        UpgradeCtx memory u;
        u.sizeFactory = SizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);
        u.owner = contracts[block.chainid][Contract.SIZE_GOVERNANCE];

        // Legacy markets we will migrate (unpaused only).
        u.legacyMarkets = getUnpausedSizeMarkets(u.sizeFactory);
        require(u.legacyMarkets.length > 0, "no unpaused markets found");

        // New implementations to be referenced by the upgrade tx.
        u.newSizeFactoryImplementation = address(new SizeFactory());
        console.log(
            "ProposeSafeTxUpgradeToV1_9_part_1_Script: newSizeFactoryImplementation", u.newSizeFactoryImplementation
        );

        u.needsLegacySizeUpgrade = _needsLegacySizeUpgrade(u.legacyMarkets);
        if (u.needsLegacySizeUpgrade) {
            // Base Sepolia legacy markets are still v1.8 and must be upgraded before shutdown.
            u.newSizeImplementation = address(new Size());
            console.log("ProposeSafeTxUpgradeToV1_9_part_1_Script: newSizeImplementation", u.newSizeImplementation);
        }

        u.newRheoImplementation = address(new Rheo());
        console.log("ProposeSafeTxUpgradeToV1_9_part_1_Script: newRheoImplementation", u.newRheoImplementation);

        // Deploy a brand new Rheo FM CollectionsManager proxy and point SizeFactory to it.
        {
            address impl = address(new RheoCollectionsManager());
            console.log("ProposeSafeTxUpgradeToV1_9_part_1_Script: newCollectionsManagerImplementation", impl);
            u.newCollectionsManagerProxy = address(
                new ERC1967Proxy(
                    impl, abi.encodeCall(RheoCollectionsManager.initialize, (ISizeFactory(address(u.sizeFactory))))
                )
            );
            console.log(
                "ProposeSafeTxUpgradeToV1_9_part_1_Script: newCollectionsManagerProxy", u.newCollectionsManagerProxy
            );
        }

        // Group markets by underlying borrow token so we can:
        // 1) approve+deposit once per token (mint borrowTokenVault shares),
        // 2) withdraw once per token before pausing the anchor market.
        (u.groupBorrowTokens, u.anchors) = _groupMarketsByUnderlyingBorrowToken(u.legacyMarkets);
        u.groups = u.groupBorrowTokens.length;
        u.groupRequiredBorrowTokenLiquidity = new uint256[](u.groups);

        GetMarketShutdownCalldataScript shutdownScript = new GetMarketShutdownCalldataScript();
        for (uint256 i = 0; i < u.legacyMarkets.length; i++) {
            ISize legacy = u.legacyMarkets[i];
            address borrowToken = address(legacy.data().underlyingBorrowToken);
            uint256 group = _findBorrowTokenGroupIndex(u.groupBorrowTokens, borrowToken);

            shutdownScript.collectPositions(legacy);
            u.groupRequiredBorrowTokenLiquidity[group] += shutdownScript.getSumFutureValue(legacy);
        }

        u.depositGroups = 0;
        for (uint256 g = 0; g < u.groups; g++) {
            uint256 ownerBalance = IERC20Metadata(u.groupBorrowTokens[g]).balanceOf(u.owner);
            uint256 requiredLiquidity = u.groupRequiredBorrowTokenLiquidity[g];
            uint256 depositAmount = ownerBalance < requiredLiquidity ? ownerBalance : requiredLiquidity;
            if (depositAmount > 0) {
                u.depositGroups++;
            }
        }

        u.maturities = v1_9Maturities();

        // Count calls (roughly):
        // - Upgrade factory + set impls + set collections manager.
        // - For each legacy market: create Rheo market + shutdown (and pause for non-anchor markets).
        // - For each group: withdraw (always), pause anchor, plus approve+deposit+approve(0) if depositing.
        // - Remove legacy markets from factory registry.
        uint256 totalCalls = 0;
        totalCalls += 1; // upgrade sizeFactory
        totalCalls += 1; // setRheoImplementation
        totalCalls += 1; // setCollectionsManager
        if (u.needsLegacySizeUpgrade) {
            totalCalls += u.legacyMarkets.length; // upgrade legacy Size markets
            totalCalls += 1; // setSizeImplementation
        }
        totalCalls += u.legacyMarkets.length; // createMarketRheo
        totalCalls += u.legacyMarkets.length; // shutdown legacy (and pause non-anchor via multicall)
        totalCalls += u.groups; // withdraw per group
        totalCalls += u.groups; // pause anchor per group
        totalCalls += u.depositGroups * 3; // approve + deposit + approve(0) for groups with non-zero balance
        totalCalls += u.legacyMarkets.length; // remove legacy markets

        targets = new address[](totalCalls);
        datas = new bytes[](totalCalls);
        uint256 k = 0;

        // 1) Upgrade SizeFactory to v1.9.
        targets[k] = address(u.sizeFactory);
        datas[k] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (u.newSizeFactoryImplementation, ""));
        k++;

        // 2) Set Rheo implementation used for new markets.
        targets[k] = address(u.sizeFactory);
        datas[k] = abi.encodeCall(SizeFactory.setRheoImplementation, (u.newRheoImplementation));
        k++;

        // 3) Point factory to the new Rheo FM CollectionsManager.
        targets[k] = address(u.sizeFactory);
        datas[k] =
            abi.encodeCall(SizeFactory.setCollectionsManager, (ICollectionsManagerRheo(u.newCollectionsManagerProxy)));
        k++;

        // 4) If needed, upgrade all legacy markets to latest Size implementation before shutdown.
        if (u.needsLegacySizeUpgrade) {
            for (uint256 i = 0; i < u.legacyMarkets.length; i++) {
                targets[k] = address(u.legacyMarkets[i]);
                datas[k] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (u.newSizeImplementation, ""));
                k++;
            }
            targets[k] = address(u.sizeFactory);
            datas[k] = abi.encodeCall(SizeFactory.setSizeImplementation, (u.newSizeImplementation));
            k++;
        }

        // 4) Create Rheo markets (one per legacy unpaused market), copying params from the legacy Size market.
        for (uint256 i = 0; i < u.legacyMarkets.length; i++) {
            targets[k] = address(u.sizeFactory);
            datas[k] = _buildCreateMarketRheoCall(u.sizeFactory, u.legacyMarkets[i], u.maturities);
            k++;
        }

        // 5) For each borrow token group:
        //    - approve+deposit underlying borrow token (mint vault shares),
        //    - shutdown+pause non-anchor markets,
        //    - shutdown anchor (without pause),
        //    - withdraw (convert remaining shares back to underlying),
        //    - pause anchor.
        for (uint256 g = 0; g < u.groups; g++) {
            ISize anchor = u.anchors[g];
            IERC20Metadata borrowToken = IERC20Metadata(u.groupBorrowTokens[g]);
            uint256 ownerBalance = borrowToken.balanceOf(u.owner);
            uint256 requiredLiquidity = u.groupRequiredBorrowTokenLiquidity[g];
            uint256 depositAmount = ownerBalance < requiredLiquidity ? ownerBalance : requiredLiquidity;

            if (depositAmount > 0) {
                // approve(anchor, depositAmount)
                targets[k] = address(borrowToken);
                datas[k] = abi.encodeCall(IERC20.approve, (address(anchor), depositAmount));
                k++;

                // deposit into anchor (mints borrowTokenVault shares to owner).
                targets[k] = address(anchor);
                datas[k] = abi.encodeCall(
                    ISize.deposit, (DepositParams({token: address(borrowToken), amount: depositAmount, to: u.owner}))
                );
                k++;
            }

            // shutdown+pause non-anchor markets in this group
            for (uint256 i = 0; i < u.legacyMarkets.length; i++) {
                ISize legacy = u.legacyMarkets[i];
                if (address(legacy.data().underlyingBorrowToken) != address(borrowToken)) continue;
                if (legacy == anchor) continue;
                targets[k] = address(legacy);
                datas[k] = _buildMarketShutdownAndPauseCall(shutdownScript, legacy);
                k++;
            }

            // Shutdown anchor before withdrawing so liquidation claims can still pull borrowTokenVault shares from owner.
            targets[k] = address(anchor);
            datas[k] = _buildMarketShutdownCall(shutdownScript, anchor);
            k++;

            // withdraw underlying back to owner (withdraw amount is capped to balance, so safe even if 0).
            targets[k] = address(anchor);
            datas[k] = abi.encodeCall(
                ISize.withdraw, (WithdrawParams({token: address(borrowToken), amount: type(uint256).max, to: u.owner}))
            );
            k++;

            // pause anchor after withdraw.
            targets[k] = address(anchor);
            datas[k] = abi.encodeCall(ISizeAdmin.pause, ());
            k++;

            if (depositAmount > 0) {
                // approve(anchor, 0)
                targets[k] = address(borrowToken);
                datas[k] = abi.encodeCall(IERC20.approve, (address(anchor), 0));
                k++;
            }
        }

        // 6) Remove legacy markets from SizeFactory/factory registry
        //    (after shutdown/pause so borrowTokenVault transfers still work).
        for (uint256 i = 0; i < u.legacyMarkets.length; i++) {
            targets[k] = address(u.sizeFactory);
            datas[k] = abi.encodeCall(SizeFactory.removeMarket, (address(u.legacyMarkets[i])));
            k++;
        }

        require(k == totalCalls, "invalid calls count");
    }

    function _groupMarketsByUnderlyingBorrowToken(ISize[] memory markets)
        internal
        view
        returns (address[] memory groupBorrowTokens, ISize[] memory anchors)
    {
        groupBorrowTokens = new address[](markets.length);
        anchors = new ISize[](markets.length);

        uint256 groups = 0;
        for (uint256 i = 0; i < markets.length; i++) {
            address borrowToken = address(markets[i].data().underlyingBorrowToken);

            bool alreadySeen = false;
            for (uint256 j = 0; j < groups; j++) {
                if (groupBorrowTokens[j] == borrowToken) {
                    alreadySeen = true;
                    break;
                }
            }

            if (alreadySeen) continue;

            groupBorrowTokens[groups] = borrowToken;
            anchors[groups] = markets[i];
            groups++;
        }

        _unsafeSetLength(groupBorrowTokens, groups);
        _unsafeSetLength(anchors, groups);
    }

    function _unsafeSetLength(address[] memory arr, uint256 length) internal pure {
        assembly ("memory-safe") {
            mstore(arr, length)
        }
    }

    function _needsLegacySizeUpgrade(ISize[] memory legacyMarkets) internal view returns (bool) {
        for (uint256 i = 0; i < legacyMarkets.length; i++) {
            if (!Strings.equal(legacyMarkets[i].version(), "v1.8.4")) {
                return true;
            }
        }
        return false;
    }

    function _findBorrowTokenGroupIndex(address[] memory groupBorrowTokens, address borrowToken)
        internal
        pure
        returns (uint256)
    {
        for (uint256 g = 0; g < groupBorrowTokens.length; g++) {
            if (groupBorrowTokens[g] == borrowToken) {
                return g;
            }
        }
        revert("borrow token group not found");
    }

    function v1_9Maturities() public view returns (uint256[] memory maturities) {
        if (block.chainid == BASE_SEPOLIA) {
            // Testnet schedule.
            maturities = new uint256[](6);
            maturities[0] = 1_772_323_200; // 2026-03-01 00:00:00
            maturities[1] = 1_775_001_600; // 2026-04-01 00:00:00
            maturities[2] = 1_777_593_600; // 2026-05-01 00:00:00
            maturities[3] = 1_780_272_000; // 2026-06-01 00:00:00
            maturities[4] = 1_782_864_000; // 2026-07-01 00:00:00
            maturities[5] = 1_785_542_400; // 2026-08-01 00:00:00
            return maturities;
        }

        // Production schedule (non-testnet).
        maturities = new uint256[](4);
        maturities[0] = 1_774_598_400; // 2026-03-27 08:00:00
        maturities[1] = 1_782_460_800; // 2026-06-26 08:00:00
        maturities[2] = 1_790_323_200; // 2026-09-25 08:00:00
        maturities[3] = 1_798_704_000; // 2026-12-31 08:00:00
    }

    function _buildCreateMarketRheoCall(SizeFactory sizeFactory, ISize legacy, uint256[] memory maturities)
        internal
        view
        returns (bytes memory)
    {
        (
            InitializeFeeConfigParamsRheo memory fRheo,
            InitializeRiskConfigParamsRheo memory rRheo,
            InitializeOracleParamsRheo memory oRheo,
            InitializeDataParamsRheo memory dRheo
        ) = _legacyToRheoParams(sizeFactory, legacy, maturities);

        return abi.encodeCall(SizeFactory.createMarketRheo, (fRheo, rRheo, oRheo, dRheo));
    }

    function _legacyToRheoParams(SizeFactory sizeFactory, ISize legacy, uint256[] memory maturities)
        internal
        view
        returns (
            InitializeFeeConfigParamsRheo memory fRheo,
            InitializeRiskConfigParamsRheo memory rRheo,
            InitializeOracleParamsRheo memory oRheo,
            InitializeDataParamsRheo memory dRheo
        )
    {
        InitializeFeeConfigParams memory f = legacy.feeConfig();
        InitializeRiskConfigParams memory r = legacy.riskConfig();
        InitializeOracleParams memory o = legacy.oracle();

        fRheo = InitializeFeeConfigParamsRheo({
            swapFeeAPR: f.swapFeeAPR,
            fragmentationFee: f.fragmentationFee,
            liquidationRewardPercent: f.liquidationRewardPercent,
            overdueCollateralProtocolPercent: f.overdueCollateralProtocolPercent,
            collateralProtocolPercent: f.collateralProtocolPercent,
            feeRecipient: f.feeRecipient
        });

        rRheo = InitializeRiskConfigParamsRheo({
            crOpening: r.crOpening,
            crLiquidation: r.crLiquidation,
            minimumCreditBorrowToken: r.minimumCreditBorrowToken,
            minTenor: r.minTenor,
            maxTenor: r.maxTenor,
            maturities: maturities
        });

        oRheo = InitializeOracleParamsRheo({priceFeed: o.priceFeed});

        dRheo = InitializeDataParamsRheo({
            weth: contracts[block.chainid][Contract.WETH],
            underlyingCollateralToken: address(legacy.data().underlyingCollateralToken),
            underlyingBorrowToken: address(legacy.data().underlyingBorrowToken),
            variablePool: address(legacy.data().variablePool),
            borrowTokenVault: address(legacy.data().borrowTokenVault),
            sizeFactory: address(sizeFactory)
        });
    }

    function _buildMarketShutdownAndPauseCall(GetMarketShutdownCalldataScript script, ISize market)
        internal
        returns (bytes memory)
    {
        MarketShutdownParams memory shutdownParams = script.collectPositions(market);
        bytes[] memory multicallDatas = new bytes[](2);
        multicallDatas[0] = abi.encodeCall(ISizeAdmin.marketShutdown, (shutdownParams));
        multicallDatas[1] = abi.encodeCall(ISizeAdmin.pause, ());
        return abi.encodeCall(IMulticall.multicall, (multicallDatas));
    }

    function _buildMarketShutdownCall(GetMarketShutdownCalldataScript script, ISize market)
        internal
        returns (bytes memory)
    {
        MarketShutdownParams memory shutdownParams = script.collectPositions(market);
        return abi.encodeCall(ISizeAdmin.marketShutdown, (shutdownParams));
    }

    function _execute(address[] memory targets, bytes[] memory datas) internal {
        require(targets.length == datas.length, "length mismatch");
        for (uint256 i = 0; i < targets.length; i++) {
            Address.functionCall(targets[i], datas[i]);
        }
    }
}
