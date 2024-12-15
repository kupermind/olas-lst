// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IBeacon {
    function implementation() external view returns (address);
}

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero lock data.
error ZeroLockData();

/// @dev Proxy initialization failed.
error InitializationFailed();

/*
* This is a Activity Module proxy contract.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a specified beacon contract.
* The upgrade logic must be located in the beacon contract.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title LockProxy - Smart contract for lock proxy
contract ActivityModuleProxy {
    // Beacon address
    address public immutable beacon;
    // OLAS address
    address public immutable olas;

    /// @dev ActivityModuleProxy constructor.
    /// @param _olas OLAS address.
    /// @param _beacon Beacon address.
    constructor(address _olas, address _beacon) {
        // Check for zero address
        if (_olas == address(0) || _beacon == address(0)) {
            revert ZeroAddress();
        }

        beacon = _beacon;
        olas = _olas;
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external payable {
        address implementation = IBeacon(beacon).implementation();

        assembly {
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