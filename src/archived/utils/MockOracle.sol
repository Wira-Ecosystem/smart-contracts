// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IOracle} from "./IOracle.sol";

contract MockOracle is IOracle {
    int256 private price;
    uint8 private tokenDecimals;

    constructor(int256 _initialPrice, uint8 _decimals) {
        price = _initialPrice;
        tokenDecimals = _decimals;
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (
            uint80(0),      // roundId
            price,          // answer (price)
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            uint80(0)       // answeredInRound
        );
    }

    function decimals() external view returns (uint8) {
        return tokenDecimals;
    }

    // Admin function to update the price (for testing)
    function setPrice(int256 _price) external {
        price = _price;
    }
}