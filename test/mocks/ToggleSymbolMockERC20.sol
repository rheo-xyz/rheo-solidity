// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {MockERC20} from "@solady/test/utils/mocks/MockERC20.sol";

contract ToggleSymbolMockERC20 is MockERC20 {
    bool public shouldRevertSymbol;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) MockERC20(name_, symbol_, decimals_) {}

    function setShouldRevertSymbol(bool _shouldRevertSymbol) external {
        shouldRevertSymbol = _shouldRevertSymbol;
    }

    function symbol() public view override returns (string memory) {
        if (shouldRevertSymbol) {
            revert("symbol unavailable");
        }
        return super.symbol();
    }
}
