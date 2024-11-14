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
    /// @param multisig Service multisig address.
    /// @return nonces Set of a single service multisig nonce.
    function getMultisigNonces(address multisig) external view virtual returns (uint256[] memory nonces) {
        nonces = new uint256[](1);
    }

    /// @dev Checks if the service multisig liveness ratio passes the defined liveness threshold.
    /// @notice The formula for calculating the ratio is the following:
    ///         currentNonce - service multisig nonce at time now (block.timestamp);
    ///         lastNonce - service multisig nonce at the previous checkpoint or staking time (tsStart);
    ///         ratio = (currentNonce - lastNonce) / (block.timestamp - tsStart).
    /// @param curNonces Current service multisig set of a single nonce.
    /// @param lastNonces Last service multisig set of a single nonce.
    /// @param ts Time difference between current and last timestamps.
    /// @return ratioPass True, if the liveness ratio passes the check.
    function isRatioPass(
        uint256[] memory curNonces,
        uint256[] memory lastNonces,
        uint256 ts
    ) external view virtual returns (bool ratioPass) {
        // If the checkpoint was called in the exact same block, the ratio is zero
        // If the current nonce is not greater than the last nonce, the ratio is zero
        if (ts > 0 && curNonces[0] > lastNonces[0]) {
            uint256 ratio = ((curNonces[0] - lastNonces[0]) * 1e18) / ts;
            ratioPass = (ratio >= livenessRatio);
        }
    }
}