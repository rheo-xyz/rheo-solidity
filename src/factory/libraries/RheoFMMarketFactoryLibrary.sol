// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";

import {
    InitializeDataParams as InitializeDataParamsRheo,
    InitializeFeeConfigParams as InitializeFeeConfigParamsRheo,
    InitializeOracleParams as InitializeOracleParamsRheo,
    InitializeRiskConfigParams as InitializeRiskConfigParamsRheo
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

library RheoMarketFactoryLibrary {
    function createMarketRheo(
        address implementation,
        address owner,
        InitializeFeeConfigParamsRheo calldata f,
        InitializeRiskConfigParamsRheo calldata r,
        InitializeOracleParamsRheo calldata o,
        InitializeDataParamsRheo calldata d
    ) external returns (IRheo market) {
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, abi.encodeCall(Rheo.initialize, (owner, f, r, o, d)));
        market = IRheo(payable(proxy));
    }
}
