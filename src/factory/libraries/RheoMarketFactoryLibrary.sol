// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {
    InitializeDataParams as InitializeDataParamsRheo,
    InitializeFeeConfigParams as InitializeFeeConfigParamsRheo,
    InitializeOracleParams as InitializeOracleParamsRheo,
    InitializeRiskConfigParams as InitializeRiskConfigParamsRheo
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

interface IRheoInitializer {
    function initialize(
        address owner,
        InitializeFeeConfigParamsRheo calldata f,
        InitializeRiskConfigParamsRheo calldata r,
        InitializeOracleParamsRheo calldata o,
        InitializeDataParamsRheo calldata d
    ) external;
}

library RheoMarketFactoryLibrary {
    function createMarketRheo(
        address implementation,
        address owner,
        InitializeFeeConfigParamsRheo calldata f,
        InitializeRiskConfigParamsRheo calldata r,
        InitializeOracleParamsRheo calldata o,
        InitializeDataParamsRheo calldata d
    ) external returns (address market) {
        ERC1967Proxy proxy =
            new ERC1967Proxy(implementation, abi.encodeCall(IRheoInitializer.initialize, (owner, f, r, o, d)));
        market = address(proxy);
    }
}
