// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ArrayUtils
 * @notice Helper library for working with dynamic arrays
 */

library ArrayUtils {
    function contains(address[] memory array, address value) internal pure returns (bool) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == value) return true;
        }
        return false;
    }

    function indexOf(address[] memory array, address value) internal pure returns (uint) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == value) return i;
        }
        revert("Value not found in array");
    }
}
