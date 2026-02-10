// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {Contract, Networks} from "@script/Networks.sol";
import {ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2Script} from
    "@script/ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2.s.sol";
import {ForkTest} from "@test/fork/ForkTest.sol";

import {SizeFactory} from "@src/factory/SizeFactory.sol";
import {ICollectionsManager} from "@src/collections/interfaces/ICollectionsManager.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";

contract DummyNewMarketV1_8_4 {
    // Rheo FM markets implement this v1.8.4+ helper, but not the legacy per-offer null-check helpers.
    function isUserDefinedLimitOrdersNull(address) external pure returns (bool, bool) {
        return (true, true);
    }
}

contract ForkProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2Test is ForkTest, Networks {
    uint256 private constant MAINNET_BLOCK = 24_385_645;
    uint256 private constant BASE_BLOCK = 41_946_442;

    function setUp() public override(ForkTest) {}

    function testFork_ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2_mainnet() public {
        _resetFork("mainnet", MAINNET_BLOCK, ETHEREUM_MAINNET);
        _executeUpgradeAndAssertFixed();
    }

    function testFork_ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2_base() public {
        _resetFork("base_archive", BASE_BLOCK, BASE_MAINNET);
        _executeUpgradeAndAssertFixed();
    }

    function _resetFork(string memory rpcAlias, uint256 blockNumber, uint256 chainId) internal {
        vm.createSelectFork(rpcAlias, blockNumber);
        vm.chainId(chainId);

        sizeFactory = SizeFactory(contracts[block.chainid][Contract.SIZE_FACTORY]);
        owner = contracts[block.chainid][Contract.SIZE_GOVERNANCE];
    }

    function _executeUpgradeAndAssertFixed() internal {
        ICollectionsManager collectionsManager = sizeFactory.collectionsManager();
        DummyNewMarketV1_8_4 market = new DummyNewMarketV1_8_4();

        // Pre-upgrade: the on-chain CollectionsManager implementation still calls the legacy
        // per-offer null-check helpers, which are not implemented by Rheo FM markets.
        vm.expectRevert();
        collectionsManager.isLoanAPRGreaterThanBorrowOfferAPRs(address(0xBEEF), 0, ISize(address(market)), 30 days);

        // Upgrade the CollectionsManager proxy via the same Safe-tx proposal flow we use in prod.
        ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2Script script =
            new ProposeSafeTxUpgradeCollectionsManagerV1_8_4_Update2Script();
        (address[] memory targets, bytes[] memory datas) = script.getUpgradeCollectionsManagerV1_8_4_Update2Data();
        for (uint256 i = 0; i < targets.length; i++) {
            vm.prank(owner);
            Address.functionCall(targets[i], datas[i]);
        }

        // Post-upgrade: the helper calls succeed against markets that only implement
        // `isUserDefinedLimitOrdersNull(address)`.
        bool ok =
            collectionsManager.isLoanAPRGreaterThanBorrowOfferAPRs(address(0xBEEF), 0, ISize(address(market)), 30 days);
        assertTrue(ok);

        ok = collectionsManager.isBorrowAPRLowerThanLoanOfferAPRs(address(0xBEEF), 0, ISize(address(market)), 30 days);
        assertTrue(ok);
    }
}
