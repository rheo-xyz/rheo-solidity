// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {BaseScript} from "@script/BaseScript.sol";
import {Contract, Networks} from "@script/Networks.sol";

import {SizeFactory} from "@src/factory/SizeFactory.sol";

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
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
    bool isTestnet;

    modifier parseEnv() {
        // Testnets use an EOA admin flow (no multisig), mainnets use Safe proposals.
        isTestnet = _isTestnet(block.chainid);

        if (!isTestnet) {
            safe.initialize(contracts[block.chainid][Contract.SIZE_GOVERNANCE]);
            if (!vm.envOr("SKIP_PROPOSE", false)) {
                signer = vm.envAddress("SIGNER");
                derivationPath = vm.envString("LEDGER_PATH");
            }
        }

        _;
    }

    function run() public parseEnv {
        console.log("ProposeSafeTxUpgradeToV1_9_part_2_Script");

        vm.startBroadcast();
        (address[] memory targets, bytes[] memory datas) = getUpgradeToV1_9Part2Data();

        // Log targets and raw calldatas for manual Safe transaction builder
        console.log("--- Safe transaction data (for manual GUI entry) ---");
        for (uint256 i = 0; i < targets.length; i++) {
            console.log("Tx", i, "- Target:", targets[i]);
            console.logBytes(datas[i]);
        }
        console.log("---");

        if (isTestnet) {
            _execute(targets, datas);
            vm.stopBroadcast();
        } else {
            vm.stopBroadcast();
            if (!vm.envOr("SKIP_PROPOSE", false)) {
                safe.proposeTransactions(targets, datas, signer, derivationPath);
            } else {
                console.log("Skipping proposeTransactions (SKIP_PROPOSE=1)");
            }
        }

        console.log("ProposeSafeTxUpgradeToV1_9_part_2_Script: done");
    }

    function getUpgradeToV1_9Part2Data() public view returns (address[] memory targets, bytes[] memory datas) {
        SizeFactory sizeFactory = SizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);
        IRheo[] memory unpausedRheoMarkets = getUnpausedRheoMarkets(sizeFactory);

        require(unpausedRheoMarkets.length > 0, "no unpaused markets found");

        targets = new address[](unpausedRheoMarkets.length);
        datas = new bytes[](unpausedRheoMarkets.length);
        uint256 k = 0;

        // Set overdueLiquidationRewardPercent = 0.01e18 for all currently unpaused markets.
        for (uint256 i = 0; i < unpausedRheoMarkets.length; i++) {
            targets[k] = address(unpausedRheoMarkets[i]);
            datas[k] = abi.encodeCall(
                IRheoAdmin.updateConfig,
                (
                    UpdateConfigParamsRheo({
                        key: OVERDUE_LIQUIDATION_REWARD_KEY,
                        value: OVERDUE_LIQUIDATION_REWARD_PERCENT
                    })
                )
            );
            k++;
        }

        require(k == targets.length, "invalid calls count");
    }

    function _execute(address[] memory targets, bytes[] memory datas) internal {
        require(targets.length == datas.length, "length mismatch");
        for (uint256 i = 0; i < targets.length; i++) {
            Address.functionCall(targets[i], datas[i]);
        }
    }
}
