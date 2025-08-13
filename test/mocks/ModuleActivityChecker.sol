// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ModuleActivityChecker {
    uint256 public livenessRatio;

    constructor(uint256 _livenessRatio) {
        livenessRatio = _livenessRatio;
    }

    function checkActivity(address service, uint256 timestamp) external view returns (bool) {
        return true; // Always return true for testing
    }
}
