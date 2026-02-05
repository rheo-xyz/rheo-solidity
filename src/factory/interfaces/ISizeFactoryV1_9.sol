// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    InitializeDataParams as InitializeDataParamsRheoFM,
    InitializeFeeConfigParams as InitializeFeeConfigParamsRheoFM,
    InitializeOracleParams as InitializeOracleParamsRheoFM,
    InitializeRiskConfigParams as InitializeRiskConfigParamsRheoFM
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

import {ISize as IRheoFM} from "@rheo-fm/src/market/interfaces/ISize.sol";

/// @title ISizeFactoryV1_9
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice The interface for the size factory v1.9
interface ISizeFactoryV1_9 {
    /// @notice Creates a new Rheo FM market
    /// @dev The contract owner is set as the owner of the market
    function createMarketRheoFM(
        InitializeFeeConfigParamsRheoFM calldata feeConfigParamsRheoFM,
        InitializeRiskConfigParamsRheoFM calldata riskConfigParamsRheoFM,
        InitializeOracleParamsRheoFM calldata oracleParamsRheoFM,
        InitializeDataParamsRheoFM calldata dataParamsRheoFM
    ) external returns (IRheoFM);

    /// @notice Set the rheo fm implementation
    /// @param _rheoFMImplementation The new rheo fm implementation
    function setRheoFMImplementation(address _rheoFMImplementation) external;
}
