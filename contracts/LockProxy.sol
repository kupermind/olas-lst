// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Zero implementation address.
error ZeroImplementationAddress();

/// @dev Zero lock data.
error ZeroLockData();

/// @dev Proxy initialization failed.
error InitializationFailed();

/*
* This is a veOLAS lock proxy contract.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Special lock implementation address slot is produced by hashing the "LOCK_PROXY"
* string in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title LockProxy - Smart contract for lock proxy
contract LockProxy {
    // Code position in storage is keccak256("LOCK_PROXY") = "0xba0510ba4ac8fe0cfe7be4f1ee5a33bd685e39302141a027f3ed976559b2fa17"
    bytes32 public constant LOCK_PROXY = 0xba0510ba4ac8fe0cfe7be4f1ee5a33bd685e39302141a027f3ed976559b2fa17;

    /// @dev LockProxy constructor.
    /// @param implementation veOLAS lock implementation address.
    /// @param lockData veOLAS lock initialization data.
    constructor(address implementation, bytes memory lockData) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (implementation == address(0)) {
            revert ZeroImplementationAddress();
        }

        // Check for the zero data
        if (lockData.length == 0) {
            revert ZeroLockData();
        }

        // Store the lock implementation address
        assembly {
            sstore(LOCK_PROXY, implementation)
        }
        // Initialize proxy tokenomics storage
        (bool success, ) = implementation.delegatecall(lockData);
        if (!success) {
            revert InitializationFailed();
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external {
        assembly {
            let implementation := sload(LOCK_PROXY)
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }
}