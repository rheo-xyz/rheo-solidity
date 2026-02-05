// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Size as RheoFM} from "@rheo-fm/src/market/Size.sol";
import {ISize as IRheoFM} from "@rheo-fm/src/market/interfaces/ISize.sol";

import {
    InitializeDataParams as InitializeDataParamsRheoFM,
    InitializeFeeConfigParams as InitializeFeeConfigParamsRheoFM,
    InitializeOracleParams as InitializeOracleParamsRheoFM,
    InitializeRiskConfigParams as InitializeRiskConfigParamsRheoFM
} from "@rheo-fm/src/market/libraries/actions/Initialize.sol";

library RheoFMMarketFactoryLibrary {
    function createMarketRheoFM(
        address implementation,
        address owner,
        InitializeFeeConfigParamsRheoFM calldata f,
        InitializeRiskConfigParamsRheoFM calldata r,
        InitializeOracleParamsRheoFM calldata o,
        InitializeDataParamsRheoFM calldata d
    ) external returns (IRheoFM market) {
        ERC1967Proxy proxy =
            new ERC1967Proxy(implementation, abi.encodeCall(RheoFM.initialize, (owner, f, r, o, d)));
        market = IRheoFM(payable(proxy));
    }
}
