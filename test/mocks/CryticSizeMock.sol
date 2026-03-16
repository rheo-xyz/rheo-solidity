// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Size} from "@src/market/Size.sol";
import {State} from "@src/market/SizeStorage.sol";
import {AccountingLibrary} from "@src/market/libraries/AccountingLibrary.sol";
import {RiskLibrary} from "@src/market/libraries/RiskLibrary.sol";
import {CREDIT_POSITION_ID_START, DEBT_POSITION_ID_START, LoanLibrary, LoanStatus} from "@src/market/libraries/LoanLibrary.sol";

contract CryticSizeMock is Size {
    using LoanLibrary for State;
    using AccountingLibrary for State;
    using RiskLibrary for State;

    // https://github.com/foundry-rs/foundry/issues/4615
    bool public IS_TEST = true;

    function isCreditPositionId(uint256 creditPositionId) external view returns (bool) {
        return state.isCreditPositionId(creditPositionId);
    }

    function getLoanStatus(uint256 positionId) external view returns (LoanStatus) {
        return state.getLoanStatus(positionId);
    }

    function getPositionsCount() external view returns (uint256, uint256) {
        return (
            state.data.nextDebtPositionId - DEBT_POSITION_ID_START,
            state.data.nextCreditPositionId - CREDIT_POSITION_ID_START
        );
    }
}
