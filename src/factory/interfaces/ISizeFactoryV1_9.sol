// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @title ISizeFactoryV1_9
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice The interface for the size factory v1.9
/// @dev `createMarketRheo` moved to ISizeFactoryV2 in v2.0: Rheo FM markets now take a basket of collateral assets,
///      which changed the initialization parameters.
interface ISizeFactoryV1_9 {
    /// @notice Set the Rheo implementation
    /// @param _rheoImplementation The new Rheo implementation
    function setRheoImplementation(address _rheoImplementation) external;

    /// @notice Check if an address is a registered Rheo market
    /// @param candidate The candidate market to check
    /// @return True if the candidate is a registered Rheo market
    function isRheoMarket(address candidate) external view returns (bool);
}
