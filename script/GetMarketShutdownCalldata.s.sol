// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {BaseScript} from "@script/BaseScript.sol";
import {Contract, Networks} from "@script/Networks.sol";

import {DataView} from "@src/market/SizeViewData.sol";
import {ISize} from "@src/market/interfaces/ISize.sol";
import {ISizeAdmin} from "@src/market/interfaces/ISizeAdmin.sol";
import {ISizeView} from "@src/market/interfaces/ISizeView.sol";
import {
    CREDIT_POSITION_ID_START,
    CreditPosition,
    DEBT_POSITION_ID_START,
    DebtPosition
} from "@src/market/libraries/LoanLibrary.sol";
import {MarketShutdownParams} from "@src/market/libraries/actions/MarketShutdown.sol";

contract GetMarketShutdownCalldataScript is BaseScript, Networks {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(ISize market => EnumerableSet.AddressSet) private borrowersByMarket;
    mapping(ISize market => EnumerableSet.AddressSet) private lendersByMarket;
    mapping(ISize market => EnumerableSet.UintSet) private debtPositionIdsByMarket;
    mapping(ISize market => EnumerableSet.UintSet) private creditPositionIdsByMarket;
    mapping(ISize market => uint256) private sumFutureValueByMarket;

    address[10] private extraUsersWithCollateral = [
        0x83eCCb05386B2d10D05e1BaEa8aC89b5B7EA8290,
        0x12328eA44AB6D7B18aa9Cc030714763734b625dB,
        0x52f5E8A5E68fafcAc57b56bf62b886424d008dfd,
        0x2c2666015F604835b0f629F9884D764BaDE89C30,
        0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045,
        0x5D58EDC7a7C91239Ec2FD56a646679780886323c,
        0x8FF4E2A794b612360dc8e4A4f153A1A4672231e6,
        0xAa44D09F81C5D256603E142267E39867B2B12cc2,
        0x178d527703888230b78e733cb777A50F53D5fCca,
        0x3003650b7E4Ae5d43d48fa33F43dF43781Ab1FbF
    ];

    function run() public pure {}

    function getMarketShutdownCalldata(ISize market) public returns (bytes memory calldata_) {
        MarketShutdownParams memory shutdownParams = collectPositions(market);
        calldata_ = abi.encodeCall(ISizeAdmin.marketShutdown, (shutdownParams));
    }

    function getBorrowers(ISize market) external view returns (address[] memory) {
        return borrowersByMarket[market].values();
    }

    function getLenders(ISize market) external view returns (address[] memory) {
        return lendersByMarket[market].values();
    }

    function getDebtPositionIds(ISize market) external view returns (uint256[] memory) {
        return debtPositionIdsByMarket[market].values();
    }

    function getCreditPositionIds(ISize market) external view returns (uint256[] memory) {
        return creditPositionIdsByMarket[market].values();
    }

    function getSumFutureValue(ISize market) external view returns (uint256) {
        return sumFutureValueByMarket[market];
    }

    function collectPositions(ISize market) public returns (MarketShutdownParams memory params) {
        ISizeView marketView = ISizeView(address(market));
        DataView memory dataView = marketView.data();

        EnumerableSet.AddressSet storage borrowers = borrowersByMarket[market];
        EnumerableSet.AddressSet storage lenders = lendersByMarket[market];
        EnumerableSet.UintSet storage debtPositionIds = debtPositionIdsByMarket[market];
        EnumerableSet.UintSet storage creditPositionIds = creditPositionIdsByMarket[market];

        borrowers.clear();
        lenders.clear();
        debtPositionIds.clear();
        creditPositionIds.clear();
        sumFutureValueByMarket[market] = 0;

        for (
            uint256 debtPositionId = DEBT_POSITION_ID_START;
            debtPositionId < dataView.nextDebtPositionId;
            debtPositionId++
        ) {
            DebtPosition memory debtPosition = marketView.getDebtPosition(debtPositionId);
            if (debtPosition.futureValue > 0) {
                borrowers.add(debtPosition.borrower);
                debtPositionIds.add(debtPositionId);
                sumFutureValueByMarket[market] += debtPosition.futureValue;
            } else if (dataView.collateralToken.balanceOf(debtPosition.borrower) > 0) {
                borrowers.add(debtPosition.borrower);
            }
        }

        for (
            uint256 creditPositionId = CREDIT_POSITION_ID_START;
            creditPositionId < dataView.nextCreditPositionId;
            creditPositionId++
        ) {
            CreditPosition memory creditPosition = marketView.getCreditPosition(creditPositionId);
            lenders.add(creditPosition.lender);

            // Some lenders can still hold collateral shares even when their credit positions are null.
            // Include them in force-withdraw to ensure collateralToken totalSupply reaches 0 on shutdown.
            if (dataView.collateralToken.balanceOf(creditPosition.lender) > 0) {
                borrowers.add(creditPosition.lender);
            }

            if (creditPosition.credit == 0 || !debtPositionIds.contains(creditPosition.debtPositionId)) {
                continue;
            }

            creditPositionIds.add(creditPositionId);
        }

        borrowers.add(marketView.feeConfig().feeRecipient);
        borrowers.add(contracts[block.chainid][Contract.SIZE_GOVERNANCE]);
        for (uint256 i = 0; i < extraUsersWithCollateral.length; i++) {
            borrowers.add(extraUsersWithCollateral[i]);
        }

        params = MarketShutdownParams({
            debtPositionIdsToForceLiquidate: debtPositionIds.values(),
            creditPositionIdsToClaim: creditPositionIds.values(),
            usersToForceWithdraw: borrowers.values(),
            shouldCheckSupply: true
        });
    }
}
