// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero value.
error ZeroValue();

/// @title MockActivityChecker - Smart contract for performing service staking activity check
contract MockActivityChecker {
    // Liveness ratio in the format of 1e18
    uint256 public immutable livenessRatio;

    /// @dev MockActivityChecker constructor.
    /// @param _livenessRatio Liveness ratio in the format of 1e18.
    constructor(uint256 _livenessRatio) {
        // Check for zero value
        if (_livenessRatio == 0) {
            revert ZeroValue();
        }

        livenessRatio = _livenessRatio;
    }

    /// @dev Gets service multisig nonces.
    /// @return nonces Set of a single service multisig nonce.
    function getMultisigNonces(address) external view virtual returns (uint256[] memory nonces) {
        nonces = new uint256[](1);
    }

    /// @dev Checks if the service multisig liveness ratio passes the defined liveness threshold.
    function isRatioPass(
        uint256[] memory,
        uint256[] memory,
        uint256
    ) external view virtual returns (bool) {
        return true;
    }
}