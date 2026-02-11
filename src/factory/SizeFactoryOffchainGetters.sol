// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math, PERCENT} from "@src/market/libraries/Math.sol";

import {ISizeFactoryOffchainGetters} from "@src/factory/interfaces/ISizeFactoryOffchainGetters.sol";

import {SizeFactoryStorage} from "@src/factory/SizeFactoryStorage.sol";
import {ActionsBitmap, Authorization} from "@src/factory/libraries/Authorization.sol";

import {VERSION as FACTORY_VERSION} from "@rheo-fm/src/market/interfaces/IRheo.sol";

/// @title SizeFactoryOffchainGetters
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice See the documentation in {ISizeFactory}.
abstract contract SizeFactoryOffchainGetters is ISizeFactoryOffchainGetters, SizeFactoryStorage {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes4 private constant DATA_SELECTOR = bytes4(keccak256("data()"));
    bytes4 private constant RISK_CONFIG_SELECTOR = bytes4(keccak256("riskConfig()"));
    bytes4 private constant ORACLE_SELECTOR = bytes4(keccak256("oracle()"));
    bytes4 private constant VERSION_SELECTOR = bytes4(keccak256("version()"));

    /// @inheritdoc ISizeFactoryOffchainGetters
    function getMarket(uint256 index) external view returns (address) {
        return markets.at(index);
    }

    /// @inheritdoc ISizeFactoryOffchainGetters
    function getMarketsCount() external view returns (uint256) {
        return markets.length();
    }

    /// @inheritdoc ISizeFactoryOffchainGetters
    function getMarkets() external view returns (address[] memory _markets) {
        _markets = new address[](markets.length());
        for (uint256 i = 0; i < _markets.length; i++) {
            _markets[i] = markets.at(i);
        }
    }

    /// @inheritdoc ISizeFactoryOffchainGetters
    function getMarketDescriptions() external view returns (string[] memory descriptions) {
        descriptions = new string[](markets.length());
        // slither-disable-start calls-loop
        for (uint256 i = 0; i < descriptions.length; i++) {
            descriptions[i] = _getMarketDescription(markets.at(i));
        }
        // slither-disable-end calls-loop
    }

    function _getMarketDescription(address market) private view returns (string memory description) {
        string memory marketType = _isRheoMarket(market) ? "Rheo" : "Size";
        (address collateralToken, address borrowToken, bool hasData) = _tryGetMarketData(market);
        (uint256 crLiquidationPercent, bool hasRiskConfig) = _tryGetCrLiquidationPercent(market);
        if (!hasData || !hasRiskConfig) {
            return string.concat(marketType, " | ", Strings.toHexString(market));
        }

        // slither-disable-next-line calls-loop
        string memory collateralSymbol = IERC20Metadata(collateralToken).symbol();
        // slither-disable-next-line calls-loop
        string memory borrowSymbol = IERC20Metadata(borrowToken).symbol();
        string memory marketVersion = _getVersion(market);

        return string.concat(
            marketType,
            " | ",
            collateralSymbol,
            " | ",
            borrowSymbol,
            " | ",
            Strings.toString(crLiquidationPercent),
            " | ",
            marketVersion
        );
    }

    function _tryGetMarketData(address market)
        private
        view
        returns (address collateralToken, address borrowToken, bool)
    {
        // slither-disable-next-line calls-loop
        (bool success, bytes memory marketData) = market.staticcall(abi.encodeWithSelector(DATA_SELECTOR));
        if (!success || marketData.length < 128) {
            return (address(0), address(0), false);
        }

        assembly ("memory-safe") {
            collateralToken := mload(add(marketData, 0x60))
            borrowToken := mload(add(marketData, 0x80))
        }
        return (collateralToken, borrowToken, true);
    }

    function _tryGetCrLiquidationPercent(address market) private view returns (uint256 crLiquidationPercent, bool) {
        // slither-disable-next-line calls-loop
        (bool success, bytes memory riskConfigData) = market.staticcall(abi.encodeWithSelector(RISK_CONFIG_SELECTOR));
        if (!success || riskConfigData.length < 64) {
            return (0, false);
        }

        uint256 head0;
        uint256 crLiquidation;
        assembly ("memory-safe") {
            head0 := mload(add(riskConfigData, 0x20))
            crLiquidation := mload(add(riskConfigData, 0x40))
        }
        // Rheo riskConfig() returns a dynamic tuple and starts with an offset word (0x20),
        // so the second field (crLiquidation) is shifted by one word compared to Size.
        if (head0 == 0x20) {
            if (riskConfigData.length < 96) {
                return (0, false);
            }
            assembly ("memory-safe") {
                crLiquidation := mload(add(riskConfigData, 0x60))
            }
        }
        return (Math.mulDivDown(100, crLiquidation, PERCENT), true);
    }

    function _isRheoMarket(address market) internal view returns (bool) {
        // Size markets return (address,uint64) for oracle(), while Rheo markets return (address).
        // slither-disable-next-line calls-loop
        (bool success, bytes memory result) = market.staticcall(abi.encodeWithSelector(ORACLE_SELECTOR));
        return success && result.length == 32;
    }

    function _getVersion(address market) private view returns (string memory marketVersion) {
        // slither-disable-next-line calls-loop
        (bool success, bytes memory versionData) = market.staticcall(abi.encodeWithSelector(VERSION_SELECTOR));
        if (!success) {
            revert();
        }

        marketVersion = abi.decode(versionData, (string));
    }

    /// @inheritdoc ISizeFactoryOffchainGetters
    function isAuthorizedAll(address operator, address onBehalfOf, ActionsBitmap actionsBitmap)
        external
        view
        returns (bool)
    {
        if (operator == onBehalfOf) {
            return true;
        } else {
            uint256 nonce = authorizationNonces[onBehalfOf];
            ActionsBitmap authorizationsActionsBitmap = authorizations[nonce][operator][onBehalfOf];
            return Authorization.toUint256(authorizationsActionsBitmap) & Authorization.toUint256(actionsBitmap)
                == Authorization.toUint256(actionsBitmap);
        }
    }

    /// @inheritdoc ISizeFactoryOffchainGetters
    function version() external pure returns (string memory) {
        return FACTORY_VERSION;
    }
}
