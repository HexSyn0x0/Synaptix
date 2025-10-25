// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MathUtils
 * @notice Collection of advanced math utilities for Synaptix contracts
 * @dev Fixed point arithmetic, safe division, power functions
 */

library MathUtils {
    uint256 constant WAD = 1e18;

    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b + WAD / 2) / WAD;
    }

    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "Division by zero");
        return (a * WAD + b / 2) / b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    // Exponentiation by squaring
    function wadPow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? x : WAD;
        for (n /= 2; n != 0; n /= 2) {
            x = wadMul(x, x);
            if (n % 2 != 0) {
                z = wadMul(z, x);
            }
        }
    }
}
