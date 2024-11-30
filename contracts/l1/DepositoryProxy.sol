// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Zero implementation address.
error ZeroImplementationAddress();

/// @dev Zero depository data.
error ZeroDepositoryData();

/// @dev Proxy initialization failed.
error InitializationFailed();

/*
* This is a Depository proxy contract.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Special depository implementation address slot is produced by hashing the "DEPOSITORY_PROXY"
* string in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title DepositoryProxy - Smart contract for depository proxy
contract DepositoryProxy {
    // Code position in storage is keccak256("DEPOSITORY_PROXY") = "0x40f951bb727bcaf251807e38aa34e1b3f20d890f9f3286454f4c473c60a21cdc"
    bytes32 public constant DEPOSITORY_PROXY = 0x40f951bb727bcaf251807e38aa34e1b3f20d890f9f3286454f4c473c60a21cdc;

    /// @dev DepositoryProxy constructor.
    /// @param implementation Depository implementation address.
    /// @param depositoryData Depository initialization data.
    constructor(address implementation, bytes memory depositoryData) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (implementation == address(0)) {
            revert ZeroImplementationAddress();
        }

        // Check for the zero data
        if (depositoryData.length == 0) {
            revert ZeroDepositoryData();
        }

        // Store the depository implementation address
        assembly {
            sstore(DEPOSITORY_PROXY, implementation)
        }
        // Initialize proxy tokenomics storage
        (bool success, ) = implementation.delegatecall(depositoryData);
        if (!success) {
            revert InitializationFailed();
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external {
        assembly {
            let implementation := sload(DEPOSITORY_PROXY)
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