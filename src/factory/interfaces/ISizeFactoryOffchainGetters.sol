// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ActionsBitmap} from "@src/factory/libraries/Authorization.sol";

/// @title ISizeFactoryGetters
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice The interface for the size factory getters. These functions are only used by offchain components.
interface ISizeFactoryOffchainGetters {
    /// @notice Get a market by index
    /// @param index The index of the market
    /// @return market The market
    function getMarket(uint256 index) external view returns (address);

    /// @notice Get the number of markets
    /// @return marketsCount The number of markets
    function getMarketsCount() external view returns (uint256);

    /// @notice Get all markets
    /// @return markets The markets
    function getMarkets() external view returns (address[] memory);

    /// @notice Get all market descriptions
    ///         The market description is Size | COLLATERALSYMBOL | BORROWSYMBOL | CRLPERCENT | VERSION
    ///         or Rheo | COLLATERALSYMBOL | BORROWSYMBOL | CRLPERCENT | VERSION
    ///         such as Size | WETH | USDC | 130 | v1.2.1, for a ETH/USDC market with 130% CR
    /// @return descriptions The market descriptions
    function getMarketDescriptions() external view returns (string[] memory descriptions);

    /// @notice Check if an address is authorized for all actions
    /// @param operator The operator to check
    /// @param onBehalfOf The account on behalf of which the action is authorized
    /// @param actionsBitmap The actions bitmap
    /// @return authorized True if the address is authorized for all actions
    function isAuthorizedAll(address operator, address onBehalfOf, ActionsBitmap actionsBitmap)
        external
        view
        returns (bool);

    /// @notice Get the version of the size factory
    /// @return version The version of the size factory
    function version() external view returns (string memory);
}
