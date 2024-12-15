// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Zero address.
error ZeroAddress();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @title ActivityModule - Smart contract for veOLAS related lock and voting functions
contract ActivityModule {
    event ActivityIncreased(uint256 activityChange);

    // Activity tracker
    uint256 public activityNonce;
    // Multisig address
    address public multisig;

    function initialize(address _multisig) external {
        if (multisig != address(0)) {
            revert AlreadyInitialized();
        }

        // Check for zero address
        if (_multisig == address(0)) {
            revert ZeroAddress();
        }

        multisig = _multisig;

        // TODO: Call multisig to enable module as address(this)
    }

    function execute(bytes memory) external {
        activityNonce++;

        emit ActivityIncreased(1);
    }
}
