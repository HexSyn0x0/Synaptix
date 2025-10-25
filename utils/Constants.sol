// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Constants
 * @notice Define commonly used constants for Synaptix contracts
 */

library Constants {
    uint256 constant WAD = 1e18;
    uint256 constant RAY = 1e27;

    uint256 constant MAX_LEVERAGE = 5 * 1e18; // 5x
    uint256 constant BASE_FEE = 50;           // 0.5%
}
