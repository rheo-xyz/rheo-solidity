// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Safe} from "@safe-utils/Safe.sol";
import {BaseScript} from "@script/BaseScript.sol";
import {Contract, Networks} from "@script/Networks.sol";

import {console} from "forge-std/console.sol";

import {ISizeFactory} from "@src/factory/interfaces/ISizeFactory.sol";
import {DataView} from "@src/market/SizeViewData.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";

import {ISizeAdmin} from "@src/market/interfaces/ISizeAdmin.sol";
import {ISizeView} from "@src/market/interfaces/ISizeView.sol";
import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@src/market/libraries/actions/Initialize.sol";
import {UpdateConfigParams} from "@src/market/libraries/actions/UpdateConfig.sol";

/// @notice Creates a dummy WETH/USDC market on the factory using the same borrowTokenVault
///         as the original markets, so users can withdraw their locked USDC after all markets
///         have been shut down and removed.
contract ProposeSafeTxCreateDummyMarketScript is BaseScript, Networks {
    using Safe for *;

    address signer;
    string derivationPath;

    modifier parseEnv() {
        safe.initialize(contracts[block.chainid][Contract.SIZE_GOVERNANCE]);
        if (!vm.envOr("SKIP_PROPOSE", false)) {
            signer = vm.envAddress("SIGNER");
            derivationPath = vm.envString("LEDGER_PATH");
        }
        _;
    }

    function run() external parseEnv {
        address referenceMarket = vm.envAddress("REFERENCE_MARKET");

        (address[] memory targets, bytes[] memory datas) = getCreateDummyMarketData(referenceMarket);

        console.log("--- Safe transaction data (for manual GUI entry) ---");
        for (uint256 i = 0; i < targets.length; i++) {
            console.log("Tx", i, "- Target:", targets[i]);
            console.logBytes(datas[i]);
        }
        console.log("---");

        if (!vm.envOr("SKIP_PROPOSE", false)) {
            safe.proposeTransactions(targets, datas, signer, derivationPath);
        } else {
            console.log("Skipping proposeTransactions (SKIP_PROPOSE=1)");
        }
    }

    /// @notice Builds the createMarket + setDebtCap(0) calldata using a reference market
    ///         (old, paused market still on-chain) to source the borrowTokenVault, variablePool,
    ///         underlyingBorrowToken, and price feed.
    function getCreateDummyMarketData(address referenceMarket)
        public
        returns (address[] memory targets, bytes[] memory datas)
    {
        DataView memory refData = ISizeView(referenceMarket).data();
        InitializeOracleParams memory refOracle = ISizeView(referenceMarket).oracle();

        address factory = contracts[block.chainid][Contract.SIZE_FACTORY];

        // The factory creates markets via CREATE (delegatecall to library),
        // so we can predict the new market address from the factory's nonce.
        uint64 factoryNonce = vm.getNonce(factory);
        address predictedMarket = vm.computeCreateAddress(factory, factoryNonce);
        console.log("Predicted new market address:", predictedMarket);

        targets = new address[](2);
        datas = new bytes[](2);

        // Tx 0: Create the dummy market
        targets[0] = factory;
        datas[0] = abi.encodeCall(
            ISizeFactory.createMarket,
            (
                InitializeFeeConfigParams({
                    swapFeeAPR: 0,
                    fragmentationFee: 0,
                    liquidationRewardPercent: 0,
                    overdueCollateralProtocolPercent: 0,
                    collateralProtocolPercent: 0,
                    feeRecipient: contracts[block.chainid][Contract.SIZE_GOVERNANCE]
                }),
                InitializeRiskConfigParams({
                    crOpening: 1e21,
                    crLiquidation: 1.3e18,
                    minimumCreditBorrowToken: 1e6,
                    minTenor: 1,
                    maxTenor: 365 days
                }),
                InitializeOracleParams({
                    priceFeed: refOracle.priceFeed,
                    variablePoolBorrowRateStaleRateInterval: type(uint64).max
                }),
                InitializeDataParams({
                    weth: contracts[block.chainid][Contract.WETH],
                    underlyingCollateralToken: contracts[block.chainid][Contract.WETH],
                    underlyingBorrowToken: address(refData.underlyingBorrowToken),
                    variablePool: address(refData.variablePool),
                    borrowTokenVault: address(refData.borrowTokenVault),
                    sizeFactory: factory
                })
            )
        );

        // Tx 1: Set debtTokenCap to 0 on the new market to prevent any borrowing
        targets[1] = predictedMarket;
        datas[1] = abi.encodeCall(ISizeAdmin.updateConfig, (UpdateConfigParams({key: "debtTokenCap", value: 0})));
    }
}
