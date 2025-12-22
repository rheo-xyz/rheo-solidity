// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BaseScript} from "@script/BaseScript.sol";
import {CollectionsManager} from "@src/collections/CollectionsManager.sol";
import {ICollectionsManager} from "@src/collections/interfaces/ICollectionsManager.sol";
import {SizeFactory} from "@src/factory/SizeFactory.sol";

import {Contract, Networks} from "@script/Networks.sol";

import {Size} from "@src/market/Size.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {ISizeV1_8} from "@src/market/interfaces/v1.8/ISizeV1_8.sol";
import {console} from "forge-std/console.sol";

import {Safe} from "@safe-utils/Safe.sol";

contract ProposeSafeTxUpgradeToV1_8_2Script is BaseScript, Networks {
    using Safe for *;

    address signer;
    string derivationPath;
    SizeFactory private sizeFactory;
    ICollectionsManager private collectionsManager;

    modifier parseEnv() {
        safe.initialize(vm.envAddress("OWNER"));
        signer = vm.envAddress("SIGNER");
        derivationPath = vm.envString("LEDGER_PATH");

        _;
    }

    function run() public parseEnv {
        console.log("ProposeSafeTxUpgradeToV1_8_2Script");

        vm.startBroadcast();

        (address[] memory targets, bytes[] memory datas) = getUpgradeToV1_8_2Data();

        vm.stopBroadcast();

        safe.proposeTransactions(targets, datas, signer, derivationPath);

        console.log("ProposeSafeTxUpgradeToV1_8_2Script: done");
    }

    function getUpgradeToV1_8_2Data() public returns (address[] memory targets, bytes[] memory datas) {
        sizeFactory = SizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);

        ISize[] memory unpausedMarkets = getUnpausedMarkets(sizeFactory);

        Size newSizeImplementation = new Size();
        console.log("ProposeSafeTxUpgradeToV1_8_2Script: newSizeImplementation", address(newSizeImplementation));

        targets = new address[](unpausedMarkets.length);
        datas = new bytes[](unpausedMarkets.length);
        for (uint256 i = 0; i < unpausedMarkets.length; i++) {
            targets[i] = address(unpausedMarkets[i]);
            datas[i] = abi.encodeCall(
                UUPSUpgradeable.upgradeToAndCall,
                (address(newSizeImplementation), abi.encodeCall(ISizeV1_8.reinitialize, ()))
            );
        }
    }
}
