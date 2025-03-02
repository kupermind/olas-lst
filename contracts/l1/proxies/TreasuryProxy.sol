// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Zero implementation address.
error ZeroImplementationAddress();

/// @dev Zero treasury data.
error ZeroTreasuryData();

/// @dev Proxy initialization failed.
error InitializationFailed();

/*
* This is a Treasury proxy contract.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Special treasury implementation address slot is produced by hashing the "TREASURY_PROXY"
* string in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title TreasuryProxy - Smart contract for treasury proxy
contract TreasuryProxy {
    // Code position in storage is keccak256("TREASURY_PROXY") = "0x9b3195704d7d8da1c9110d90b2bf37e7d1d93753debd922cc1f20df74288b870"
    bytes32 public constant TREASURY_PROXY = 0x9b3195704d7d8da1c9110d90b2bf37e7d1d93753debd922cc1f20df74288b870;

    /// @dev TreasuryProxy constructor.
    /// @param implementation Treasury implementation address.
    /// @param treasuryData Treasury initialization data.
    constructor(address implementation, bytes memory treasuryData) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (implementation == address(0)) {
            revert ZeroImplementationAddress();
        }

        // Check for the zero data
        if (treasuryData.length == 0) {
            revert ZeroTreasuryData();
        }

        // Store the treasury implementation address
        assembly {
            sstore(TREASURY_PROXY, implementation)
        }
        // Initialize proxy tokenomics storage
        (bool success, ) = implementation.delegatecall(treasuryData);
        if (!success) {
            revert InitializationFailed();
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external {
        assembly {
            let implementation := sload(TREASURY_PROXY)
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