// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseScript} from "@script/BaseScript.sol";
import {IMultiSendCallOnly} from "@script/interfaces/IMultiSendCallOnly.sol";
import {SizeFactory} from "@src/factory/SizeFactory.sol";
import {ISizeFactory} from "@src/factory/interfaces/ISizeFactory.sol";
import {UpdateConfigParams} from "@src/market/libraries/actions/UpdateConfig.sol";

import {Size} from "@src/market/Size.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";

import {Contract, Networks} from "@script/Networks.sol";
import {console} from "forge-std/console.sol";

import {Safe} from "@safe-utils/Safe.sol";
import {Tenderly} from "@tenderly-utils/Tenderly.sol";

contract ProposeSafeTxUpdateConfigScript is BaseScript, Networks {
    using Safe for *;
    using Tenderly for *;

    address signer;
    string derivationPath;
    ISizeFactory private sizeFactory;

    modifier parseEnv() {
        safe.initialize(vm.envAddress("OWNER"));
        tenderly.initialize(
            vm.envString("TENDERLY_ACCOUNT_NAME"),
            vm.envString("TENDERLY_PROJECT_NAME"),
            vm.envString("TENDERLY_ACCESS_KEY")
        );
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");
        sizeFactory = ISizeFactory(vm.envAddress("SIZE_FACTORY"));

        _;
    }

    function run() public parseEnv broadcast {
        address[] memory marketAddresses = sizeFactory.getMarkets();

        string memory updateConfigKey = "swapFeeAPR";
        uint256 updateConfigValue = 0.005e18;

        uint256 sizeMarketsCount;
        for (uint256 i = 0; i < marketAddresses.length; i++) {
            if (_isSizeMarket(sizeFactory, marketAddresses[i])) {
                sizeMarketsCount++;
            }
        }

        address[] memory targets = new address[](sizeMarketsCount);
        bytes[] memory datas = new bytes[](sizeMarketsCount);

        // Size.updateConfig(key, value) for all markets
        uint256 index;
        for (uint256 i = 0; i < marketAddresses.length; i++) {
            if (!_isSizeMarket(sizeFactory, marketAddresses[i])) {
                continue;
            }
            targets[index] = marketAddresses[i];
            datas[index] = abi.encodeCall(
                Size.updateConfig, (UpdateConfigParams({key: updateConfigKey, value: updateConfigValue}))
            );
            index++;
        }

        safe.proposeTransactions(targets, datas, signer, derivationPath);

        Tenderly.VirtualTestnet[] memory vnets = tenderly.getVirtualTestnets();
        for (uint256 i = 0; i < vnets.length; i++) {
            tenderly.deleteVirtualTestnetById(vnets[i].id);
        }

        Tenderly.VirtualTestnet memory vnet = tenderly.createVirtualTestnet("update-config", block.chainid);
        tenderly.setStorageAt(vnet, safe.instance().safe, bytes32(uint256(4)), bytes32(uint256(1)));
        tenderly.sendTransaction(
            vnet.id, signer, safe.instance().safe, safe.getExecTransactionsData(targets, datas, signer, derivationPath)
        );
    }
}
