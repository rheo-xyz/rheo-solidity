// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {BaseScript} from "@script/BaseScript.sol";
import {Contract, Networks} from "@script/Networks.sol";

import {SizeFactory} from "@src/factory/SizeFactory.sol";

import {IMulticall} from "@src/market/interfaces/IMulticall.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";

import {IRheoAdmin} from "@rheo-fm/src/market/interfaces/IRheoAdmin.sol";
import {UpdateConfigParams as UpdateConfigParamsRheo} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";

import {console} from "forge-std/console.sol";

import {Safe} from "@safe-utils/Safe.sol";

contract ProposeSafeTxUpgradeToV1_9_part_2_Script is BaseScript, Networks {
    using Safe for *;

    uint256 private constant SIZE_OVERDUE_LIQUIDATION_REWARD_SLOT = 30;
    string private constant OVERDUE_LIQUIDATION_REWARD_KEY = "overdueLiquidationRewardPercent";

    struct LegacyMarketConfig {
        address market;
        address underlyingCollateralToken;
        address underlyingBorrowToken;
        address variablePool;
        address borrowTokenVault;
        uint256 overdueLiquidationRewardPercent;
    }

    address signer;
    string derivationPath;
    bool skipPropose;

    modifier parseEnv() {
        // Base Sepolia uses an EOA admin (no multisig). When SKIP_PROPOSE=true we execute the calls directly.
        skipPropose = vm.envOr("SKIP_PROPOSE", false);

        if (!skipPropose) {
            safe.initialize(contracts[block.chainid][Contract.SIZE_GOVERNANCE]);
            signer = vm.envAddress("SIGNER");
            derivationPath = vm.envString("LEDGER_PATH");
        }

        _;
    }

    function run() public parseEnv {
        console.log("ProposeSafeTxUpgradeToV1_9_part_2_Script");

        vm.startBroadcast();
        (address[] memory targets, bytes[] memory datas) = getUpgradeToV1_9Part2Data();

        if (skipPropose) {
            _execute(targets, datas);
            vm.stopBroadcast();
        } else {
            vm.stopBroadcast();
            safe.proposeTransactions(targets, datas, signer, derivationPath);
        }

        console.log("ProposeSafeTxUpgradeToV1_9_part_2_Script: done");
    }

    function getUpgradeToV1_9Part2Data() public view returns (address[] memory targets, bytes[] memory datas) {
        SizeFactory sizeFactory = SizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);
        address[] memory markets = sizeFactory.getMarkets();

        address[] memory legacyMarkets = new address[](markets.length);
        address[] memory rheoMarkets = new address[](markets.length);
        uint256 legacyCount = 0;
        uint256 rheoCount = 0;

        for (uint256 i = 0; i < markets.length; i++) {
            if (sizeFactory.isRheoMarket(markets[i])) {
                rheoMarkets[rheoCount++] = markets[i];
            } else {
                legacyMarkets[legacyCount++] = markets[i];
            }
        }
        _unsafeSetLength(legacyMarkets, legacyCount);
        _unsafeSetLength(rheoMarkets, rheoCount);

        address[] memory matchedLegacyMarkets = new address[](legacyCount);
        address[] memory matchedRheoMarkets = new address[](legacyCount);
        uint256[] memory matchedOverdueValues = new uint256[](legacyCount);
        bool[] memory usedRheo = new bool[](rheoCount);
        uint256 pairs = 0;

        for (uint256 i = 0; i < legacyCount; i++) {
            if (!PausableUpgradeable(legacyMarkets[i]).paused()) {
                continue;
            }

            LegacyMarketConfig memory legacyConfig = _legacyMarketConfig(ISize(legacyMarkets[i]));
            (bool found, uint256 rheoIndex) = _findMatchingRheoMarket(rheoMarkets, usedRheo, legacyConfig);
            if (!found) {
                continue;
            }

            usedRheo[rheoIndex] = true;
            matchedLegacyMarkets[pairs] = legacyConfig.market;
            matchedRheoMarkets[pairs] = rheoMarkets[rheoIndex];
            matchedOverdueValues[pairs] = legacyConfig.overdueLiquidationRewardPercent;
            pairs++;
        }

        require(pairs > 0, "no migrated legacy/rheo matches found");
        _unsafeSetLength(matchedLegacyMarkets, pairs);
        _unsafeSetLength(matchedRheoMarkets, pairs);
        _unsafeSetLength(matchedOverdueValues, pairs);

        targets = new address[](pairs * 2);
        datas = new bytes[](pairs * 2);
        uint256 k = 0;

        // 1) Copy overdueLiquidationRewardPercent from matched legacy Size markets to Rheo markets.
        for (uint256 i = 0; i < pairs; i++) {
            targets[k] = matchedRheoMarkets[i];
            datas[k] = _buildUpdateOverdueLiquidationRewardCall(matchedOverdueValues[i]);
            k++;
        }

        // 2) Remove matched legacy markets from SizeFactory after config copy.
        for (uint256 i = 0; i < pairs; i++) {
            targets[k] = address(sizeFactory);
            datas[k] = abi.encodeCall(SizeFactory.removeMarket, (matchedLegacyMarkets[i]));
            k++;
        }

        require(k == targets.length, "invalid calls count");
    }

    function _legacyMarketConfig(ISize legacy) internal view returns (LegacyMarketConfig memory) {
        return LegacyMarketConfig({
            market: address(legacy),
            underlyingCollateralToken: address(legacy.data().underlyingCollateralToken),
            underlyingBorrowToken: address(legacy.data().underlyingBorrowToken),
            variablePool: address(legacy.data().variablePool),
            borrowTokenVault: address(legacy.data().borrowTokenVault),
            overdueLiquidationRewardPercent: uint256(legacy.extSload(bytes32(SIZE_OVERDUE_LIQUIDATION_REWARD_SLOT)))
        });
    }

    function _findMatchingRheoMarket(
        address[] memory rheoMarkets,
        bool[] memory usedRheo,
        LegacyMarketConfig memory legacyConfig
    ) internal view returns (bool found, uint256 rheoIndex) {
        for (uint256 i = 0; i < rheoMarkets.length; i++) {
            if (usedRheo[i]) continue;

            ISize candidate = ISize(rheoMarkets[i]);
            if (
                address(candidate.data().underlyingCollateralToken) == legacyConfig.underlyingCollateralToken
                    && address(candidate.data().underlyingBorrowToken) == legacyConfig.underlyingBorrowToken
                    && address(candidate.data().variablePool) == legacyConfig.variablePool
                    && address(candidate.data().borrowTokenVault) == legacyConfig.borrowTokenVault
            ) {
                return (true, i);
            }
        }

        return (false, 0);
    }

    function _buildUpdateOverdueLiquidationRewardCall(uint256 overdueLiquidationRewardPercent)
        internal
        pure
        returns (bytes memory)
    {
        bytes[] memory multicallDatas = new bytes[](1);
        multicallDatas[0] = abi.encodeCall(
            IRheoAdmin.updateConfig,
            (UpdateConfigParamsRheo({key: OVERDUE_LIQUIDATION_REWARD_KEY, value: overdueLiquidationRewardPercent}))
        );
        return abi.encodeCall(IMulticall.multicall, (multicallDatas));
    }

    function _unsafeSetLength(address[] memory arr, uint256 length) internal pure {
        assembly ("memory-safe") {
            mstore(arr, length)
        }
    }

    function _unsafeSetLength(uint256[] memory arr, uint256 length) internal pure {
        assembly ("memory-safe") {
            mstore(arr, length)
        }
    }

    function _execute(address[] memory targets, bytes[] memory datas) internal {
        require(targets.length == datas.length, "length mismatch");
        for (uint256 i = 0; i < targets.length; i++) {
            Address.functionCall(targets[i], datas[i]);
        }
    }
}
