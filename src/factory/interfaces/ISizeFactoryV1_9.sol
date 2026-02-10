// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    InitializeDataParamsRheo,
    InitializeFeeConfigParamsRheo,
    InitializeOracleParamsRheo,
    InitializeRiskConfigParamsRheo
} from "@src/factory/interfaces/RheoMarketTypes.sol";

/// @title ISizeFactoryV1_9
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice The interface for the size factory v1.9
interface ISizeFactoryV1_9 {
    /// @notice Creates a new Rheo FM market
    /// @dev The contract owner is set as the owner of the market
    function createMarketRheo(
        InitializeFeeConfigParamsRheo calldata feeConfigParamsRheo,
        InitializeRiskConfigParamsRheo calldata riskConfigParamsRheo,
        InitializeOracleParamsRheo calldata oracleParamsRheo,
        InitializeDataParamsRheo calldata dataParamsRheo
    ) external returns (address);

    /// @notice Set the Rheo implementation
    /// @param _rheoImplementation The new Rheo implementation
    function setRheoImplementation(address _rheoImplementation) external;
}
