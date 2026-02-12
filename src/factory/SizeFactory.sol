// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IPool} from "@aave/interfaces/IPool.sol";

import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {ICollectionsManager as ICollectionsManagerRheo} from
    "@rheo-fm/src/collections/interfaces/ICollectionsManager.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {CopyLimitOrderConfig} from "@rheo-fm/src/market/libraries/OfferLibrary.sol";

import {
    InitializeDataParams,
    InitializeFeeConfigParams,
    InitializeOracleParams,
    InitializeRiskConfigParams
} from "@src/market/libraries/actions/Initialize.sol";

import {
    InitializeDataParams as InitializeDataParamsRheo,
    InitializeFeeConfigParams as InitializeFeeConfigParamsRheo,
    InitializeOracleParams as InitializeOracleParamsRheo,
    InitializeRiskConfigParams as InitializeRiskConfigParamsRheo
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Errors} from "@src/market/libraries/Errors.sol";

import {ICollectionsManager as ICollectionsManagerSize} from "@src/collections/interfaces/ICollectionsManager.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";

import {ISizeFactory} from "@src/factory/interfaces/ISizeFactory.sol";
import {ISizeFactoryV1_9} from "@src/factory/interfaces/ISizeFactoryV1_9.sol";
import {MarketFactoryLibrary} from "@src/factory/libraries/MarketFactoryLibrary.sol";
import {RheoMarketFactoryLibrary} from "@src/factory/libraries/RheoMarketFactoryLibrary.sol";

import {NonTransferrableRebasingTokenVaultLibrary} from
    "@src/factory/libraries/NonTransferrableRebasingTokenVaultLibrary.sol";
import {PriceFeedFactoryLibrary} from "@src/factory/libraries/PriceFeedFactoryLibrary.sol";
import {NonTransferrableRebasingTokenVault} from "@src/market/token/NonTransferrableRebasingTokenVault.sol";

import {PriceFeed, PriceFeedParams} from "@src/oracle/v1.5.1/PriceFeed.sol";

import {SizeFactoryEvents} from "@src/factory/SizeFactoryEvents.sol";
import {SizeFactoryOffchainGetters} from "@src/factory/SizeFactoryOffchainGetters.sol";
import {Action, ActionsBitmap, Authorization} from "@src/factory/libraries/Authorization.sol";

import {ISizeFactoryV1_7} from "@src/factory/interfaces/ISizeFactoryV1_7.sol";
import {ISizeFactoryV1_8} from "@src/factory/interfaces/ISizeFactoryV1_8.sol";

import {BORROW_RATE_UPDATER_ROLE, KEEPER_ROLE, PAUSER_ROLE} from "@src/factory/interfaces/ISizeFactory.sol";

/// @title SizeFactory
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice See the documentation in {ISizeFactory}.
/// @dev Expects `AccessControlUpgradeable` to have a single DEFAULT_ADMIN_ROLE role address set.
contract SizeFactory is
    ISizeFactory,
    SizeFactoryOffchainGetters,
    SizeFactoryEvents,
    MulticallUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        __Multicall_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(PAUSER_ROLE, _owner);
        _grantRole(KEEPER_ROLE, _owner);
        _grantRole(BORROW_RATE_UPDATER_ROLE, _owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @inheritdoc ISizeFactory
    function setSizeImplementation(address _sizeImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_sizeImplementation == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        emit SizeImplementationSet(sizeImplementation, _sizeImplementation);
        sizeImplementation = _sizeImplementation;
    }

    /// @inheritdoc ISizeFactoryV1_9
    function setRheoImplementation(address _rheoImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_rheoImplementation == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        emit RheoImplementationSet(rheoImplementation, _rheoImplementation);
        rheoImplementation = _rheoImplementation;
    }

    /// @inheritdoc ISizeFactory
    function setNonTransferrableRebasingTokenVaultImplementation(address _nonTransferrableTokenVaultImplementation)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_nonTransferrableTokenVaultImplementation == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        emit NonTransferrableRebasingTokenVaultImplementationSet(
            nonTransferrableTokenVaultImplementation, _nonTransferrableTokenVaultImplementation
        );
        nonTransferrableTokenVaultImplementation = _nonTransferrableTokenVaultImplementation;
    }

    function setCollectionsManager(ICollectionsManagerRheo _collectionsManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit CollectionsManagerSet(address(collectionsManager), address(_collectionsManager));
        collectionsManager = ICollectionsManagerSize(address(_collectionsManager));
    }

    /// @inheritdoc ISizeFactory
    function createMarket(
        InitializeFeeConfigParams calldata feeConfigParams,
        InitializeRiskConfigParams calldata riskConfigParams,
        InitializeOracleParams calldata oracleParams,
        InitializeDataParams calldata dataParams
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (ISize market) {
        address admin = msg.sender;
        market = MarketFactoryLibrary.createMarket(
            sizeImplementation, admin, feeConfigParams, riskConfigParams, oracleParams, dataParams
        );
        // slither-disable-next-line unused-return
        markets.add(address(market));
        emit CreateMarket(address(market));
    }

    /// @inheritdoc ISizeFactoryV1_9
    function createMarketRheo(
        InitializeFeeConfigParamsRheo calldata feeConfigParamsRheo,
        InitializeRiskConfigParamsRheo calldata riskConfigParamsRheo,
        InitializeOracleParamsRheo calldata oracleParamsRheo,
        InitializeDataParamsRheo calldata dataParamsRheo
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address market) {
        address admin = msg.sender;
        market = RheoMarketFactoryLibrary.createMarketRheo(
            rheoImplementation, admin, feeConfigParamsRheo, riskConfigParamsRheo, oracleParamsRheo, dataParamsRheo
        );
        // slither-disable-next-line unused-return
        markets.add(market);
        emit CreateMarket(market);
    }

    /// @inheritdoc ISizeFactory
    function removeMarket(address market) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!markets.contains(market)) {
            revert Errors.INVALID_MARKET(market);
        }
        // slither-disable-next-line unused-return
        markets.remove(market);
        emit RemoveMarket(market);
    }

    /// @inheritdoc ISizeFactory
    function createBorrowTokenVault(IPool variablePool, IERC20Metadata underlyingBorrowToken)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (NonTransferrableRebasingTokenVault borrowTokenVault)
    {
        address admin = msg.sender;
        borrowTokenVault = NonTransferrableRebasingTokenVaultLibrary.createNonTransferrableRebasingTokenVault(
            nonTransferrableTokenVaultImplementation, admin, variablePool, underlyingBorrowToken
        );
        emit CreateBorrowTokenVault(address(borrowTokenVault));
    }

    /// @inheritdoc ISizeFactory
    function createPriceFeed(PriceFeedParams memory _priceFeedParams)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (PriceFeed priceFeed)
    {
        priceFeed = PriceFeedFactoryLibrary.createPriceFeed(_priceFeedParams);
        emit CreatePriceFeed(address(priceFeed));
    }

    /// @inheritdoc ISizeFactory
    function isMarket(address candidate) public view returns (bool) {
        return markets.contains(candidate);
    }

    /// @inheritdoc ISizeFactoryV1_9
    function isRheoMarket(address candidate) public view returns (bool) {
        return markets.contains(candidate) && _isRheoMarket(candidate);
    }

    /// @inheritdoc ISizeFactoryV1_7
    function setAuthorization(address operator, ActionsBitmap actionsBitmap) external override(ISizeFactoryV1_7) {
        // validate msg.sender
        // N/A

        _setAuthorization(operator, msg.sender, actionsBitmap);
    }

    function _setAuthorization(address operator, address onBehalfOf, ActionsBitmap actionsBitmap) internal {
        // validate operator
        if (operator == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        // validate actionsBitmap
        if (!Authorization.isValid(actionsBitmap)) {
            revert Errors.INVALID_ACTIONS_BITMAP(Authorization.toUint256(actionsBitmap));
        }

        uint256 nonce = authorizationNonces[onBehalfOf];
        emit SetAuthorization(onBehalfOf, operator, Authorization.toUint256(actionsBitmap), nonce);
        authorizations[nonce][operator][onBehalfOf] = actionsBitmap;
    }

    /// @inheritdoc ISizeFactoryV1_7
    function revokeAllAuthorizations() external override(ISizeFactoryV1_7) {
        emit RevokeAllAuthorizations(msg.sender);
        authorizationNonces[msg.sender]++;
    }

    /// @inheritdoc ISizeFactoryV1_7
    function isAuthorized(address operator, address onBehalfOf, Action action) public view returns (bool) {
        if (operator == onBehalfOf) {
            return true;
        } else {
            uint256 nonce = authorizationNonces[onBehalfOf];
            return Authorization.isActionSet(authorizations[nonce][operator][onBehalfOf], action);
        }
    }

    /// @inheritdoc ISizeFactoryV1_8
    function callMarket(address market, bytes calldata data) external returns (bytes memory result) {
        if (!isMarket(market)) {
            revert Errors.INVALID_MARKET(market);
        }
        result = Address.functionCall(market, data);
    }

    /// @inheritdoc ISizeFactoryV1_8
    function subscribeToCollections(uint256[] memory collectionIds) external {
        return subscribeToCollectionsOnBehalfOf(collectionIds, msg.sender);
    }

    /// @inheritdoc ISizeFactoryV1_8
    function unsubscribeFromCollections(uint256[] memory collectionIds) external {
        return unsubscribeFromCollectionsOnBehalfOf(collectionIds, msg.sender);
    }

    /// @inheritdoc ISizeFactoryV1_8
    function subscribeToCollectionsOnBehalfOf(uint256[] memory collectionIds, address onBehalfOf) public {
        if (!isAuthorized(msg.sender, onBehalfOf, Action.MANAGE_COLLECTION_SUBSCRIPTIONS)) {
            revert Errors.UNAUTHORIZED_ACTION(msg.sender, onBehalfOf, uint8(Action.MANAGE_COLLECTION_SUBSCRIPTIONS));
        }
        ICollectionsManagerRheo(address(collectionsManager)).subscribeUserToCollections(onBehalfOf, collectionIds);
    }

    /// @inheritdoc ISizeFactoryV1_8
    function unsubscribeFromCollectionsOnBehalfOf(uint256[] memory collectionIds, address onBehalfOf) public {
        if (!isAuthorized(msg.sender, onBehalfOf, Action.MANAGE_COLLECTION_SUBSCRIPTIONS)) {
            revert Errors.UNAUTHORIZED_ACTION(msg.sender, onBehalfOf, uint8(Action.MANAGE_COLLECTION_SUBSCRIPTIONS));
        }
        ICollectionsManagerRheo(address(collectionsManager)).unsubscribeUserFromCollections(onBehalfOf, collectionIds);
    }

    function setUserCollectionCopyLimitOrderConfigs(
        uint256 collectionId,
        CopyLimitOrderConfig memory copyLoanOfferConfig,
        CopyLimitOrderConfig memory copyBorrowOfferConfig
    ) external {
        return setUserCollectionCopyLimitOrderConfigsOnBehalfOf(
            collectionId, copyLoanOfferConfig, copyBorrowOfferConfig, msg.sender
        );
    }

    function setUserCollectionCopyLimitOrderConfigsOnBehalfOf(
        uint256 collectionId,
        CopyLimitOrderConfig memory copyLoanOfferConfig,
        CopyLimitOrderConfig memory copyBorrowOfferConfig,
        address onBehalfOf
    ) public {
        if (!isAuthorized(msg.sender, onBehalfOf, Action.MANAGE_COLLECTION_SUBSCRIPTIONS)) {
            revert Errors.UNAUTHORIZED_ACTION(msg.sender, onBehalfOf, uint8(Action.MANAGE_COLLECTION_SUBSCRIPTIONS));
        }
        ICollectionsManagerRheo(address(collectionsManager)).setUserCollectionCopyLimitOrderConfigs(
            onBehalfOf, collectionId, copyLoanOfferConfig, copyBorrowOfferConfig
        );
    }

    /// @inheritdoc ISizeFactoryV1_8
    function getLoanOfferAPR(address user, uint256 collectionId, address market, address rateProvider, uint256 tenor)
        external
        view
        returns (uint256)
    {
        return ICollectionsManagerRheo(address(collectionsManager)).getLoanOfferAPR(
            user, collectionId, IRheo(market), rateProvider, tenor
        );
    }

    /// @inheritdoc ISizeFactoryV1_8
    function getBorrowOfferAPR(address user, uint256 collectionId, address market, address rateProvider, uint256 tenor)
        external
        view
        returns (uint256)
    {
        return ICollectionsManagerRheo(address(collectionsManager)).getBorrowOfferAPR(
            user, collectionId, IRheo(market), rateProvider, tenor
        );
    }

    function isBorrowAPRLowerThanLoanOfferAPRs(address user, uint256 borrowAPR, address market, uint256 tenor)
        external
        view
        returns (bool)
    {
        return ICollectionsManagerRheo(address(collectionsManager)).isBorrowAPRLowerThanLoanOfferAPRs(
            user, borrowAPR, IRheo(market), tenor
        );
    }

    function isLoanAPRGreaterThanBorrowOfferAPRs(address user, uint256 loanAPR, address market, uint256 tenor)
        external
        view
        returns (bool)
    {
        return ICollectionsManagerRheo(address(collectionsManager)).isLoanAPRGreaterThanBorrowOfferAPRs(
            user, loanAPR, IRheo(market), tenor
        );
    }
}
