// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    InitializeDataParams as InitializeDataParamsRheo,
    InitializeFeeConfigParams as InitializeFeeConfigParamsRheo,
    InitializeRiskConfigParams as InitializeRiskConfigParamsRheo
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

/// @title ISizeFactoryV2
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice The interface for the size factory v2
/// @dev Supersedes the `createMarketRheo` of ISizeFactoryV1_9. Rheo FM v2.0 markets accept a basket of collateral
///      assets, each carrying its own price feed, so the oracle parameters are no longer passed separately.
interface ISizeFactoryV2 {
    /// @notice Creates a new Rheo FM market
    /// @dev The contract owner is set as the owner of the market
    function createMarketRheo(
        InitializeFeeConfigParamsRheo calldata feeConfigParamsRheo,
        InitializeRiskConfigParamsRheo calldata riskConfigParamsRheo,
        InitializeDataParamsRheo calldata dataParamsRheo
    ) external returns (address);
}
