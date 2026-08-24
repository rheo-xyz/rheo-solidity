// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {
    InitializeDataParams as InitializeDataParamsRheo,
    InitializeFeeConfigParams as InitializeFeeConfigParamsRheo,
    InitializeRiskConfigParams as InitializeRiskConfigParamsRheo
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

interface IRheoInitializer {
    function initialize(
        address owner,
        InitializeFeeConfigParamsRheo calldata f,
        InitializeRiskConfigParamsRheo calldata r,
        InitializeDataParamsRheo calldata d
    ) external;
}

library RheoMarketFactoryLibrary {
    function createMarketRheo(
        address implementation,
        address owner,
        InitializeFeeConfigParamsRheo calldata f,
        InitializeRiskConfigParamsRheo calldata r,
        InitializeDataParamsRheo calldata d
    ) external returns (address market) {
        ERC1967Proxy proxy =
            new ERC1967Proxy(implementation, abi.encodeCall(IRheoInitializer.initialize, (owner, f, r, d)));
        market = address(proxy);
    }
}
