// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ProposeSafeTxUpgradeToV1_9_part_1_Script} from "@script/ProposeSafeTxUpgradeToV1_9_part_1.s.sol";

/// @notice Backward-compatible alias for the first phase of the v1.9 migration.
///         Use `ProposeSafeTxUpgradeToV1_9_part_1_Script` and `ProposeSafeTxUpgradeToV1_9_part_2_Script`
///         sequentially for the full migration.
contract ProposeSafeTxUpgradeToV1_9Script is ProposeSafeTxUpgradeToV1_9_part_1_Script {}
