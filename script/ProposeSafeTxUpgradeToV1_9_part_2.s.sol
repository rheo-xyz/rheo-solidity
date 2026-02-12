// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {BaseScript} from "@script/BaseScript.sol";
import {Contract, Networks} from "@script/Networks.sol";

import {SizeFactory} from "@src/factory/SizeFactory.sol";

import {IMulticall} from "@src/market/interfaces/IMulticall.sol";

import {IRheoAdmin} from "@rheo-fm/src/market/interfaces/IRheoAdmin.sol";
import {UpdateConfigParams as UpdateConfigParamsRheo} from "@rheo-fm/src/market/libraries/actions/UpdateConfig.sol";

import {console} from "forge-std/console.sol";

import {Safe} from "@safe-utils/Safe.sol";

contract ProposeSafeTxUpgradeToV1_9_part_2_Script is BaseScript, Networks {
    using Safe for *;

    uint256 private constant OVERDUE_LIQUIDATION_REWARD_PERCENT = 0.01e18;
    string private constant OVERDUE_LIQUIDATION_REWARD_KEY = "overdueLiquidationRewardPercent";

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

        uint256 unpausedMarketsCount = 0;
        for (uint256 i = 0; i < markets.length; i++) {
            if (!PausableUpgradeable(markets[i]).paused()) {
                unpausedMarketsCount++;
            }
        }
        require(unpausedMarketsCount > 0, "no unpaused markets found");

        targets = new address[](unpausedMarketsCount);
        datas = new bytes[](unpausedMarketsCount);
        uint256 k = 0;

        // Set overdueLiquidationRewardPercent = 0.01e18 for all currently unpaused markets.
        for (uint256 i = 0; i < markets.length; i++) {
            if (PausableUpgradeable(markets[i]).paused()) {
                continue;
            }
            targets[k] = markets[i];
            datas[k] = _buildUpdateOverdueLiquidationRewardCall(OVERDUE_LIQUIDATION_REWARD_PERCENT);
            k++;
        }

        require(k == targets.length, "invalid calls count");
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

    function _execute(address[] memory targets, bytes[] memory datas) internal {
        require(targets.length == datas.length, "length mismatch");
        for (uint256 i = 0; i < targets.length; i++) {
            Address.functionCall(targets[i], datas[i]);
        }
    }
}
