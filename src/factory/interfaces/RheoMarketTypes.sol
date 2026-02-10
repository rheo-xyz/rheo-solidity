// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @notice Minimal copies of Rheo FM initializer structs.
/// @dev We intentionally keep these in-repo and prefixed with `Rheo` to avoid
///      importing the full `@rheo-fm` source tree (which causes symbol clashes in Slither).
struct InitializeFeeConfigParamsRheo {
    uint256 swapFeeAPR;
    uint256 fragmentationFee;
    uint256 liquidationRewardPercent;
    uint256 overdueCollateralProtocolPercent;
    uint256 collateralProtocolPercent;
    address feeRecipient;
}

struct InitializeRiskConfigParamsRheo {
    uint256 crOpening;
    uint256 crLiquidation;
    uint256 minimumCreditBorrowToken;
    uint256 minTenor;
    uint256 maxTenor;
    uint256[] maturities;
}

struct InitializeOracleParamsRheo {
    address priceFeed;
}

struct InitializeDataParamsRheo {
    address weth;
    address underlyingCollateralToken;
    address underlyingBorrowToken;
    address variablePool;
    address borrowTokenVault;
    address sizeFactory;
}

