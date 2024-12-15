// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IBeacon {
    function implementation() external view returns (address);
}

/// @dev Zero address.
error ZeroAddress();

/*
* This is a Activity Module proxy contract.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1967.
* The implementation address must be located in a specified beacon contract.
* The upgrade logic must be located in the beacon contract.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title LockProxy - Smart contract for lock proxy
contract ActivityModuleProxy {
    // bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1))
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    // OLAS address
    address public immutable olas;

    /// @dev ActivityModuleProxy constructor.
    /// @param _olas OLAS address.
    /// @param _beacon Beacon address.
    constructor(address _olas, address _beacon) {
        // Check for zero address
        if (_beacon == address(0)) {
            revert ZeroAddress();
        }

        // Store the beacon address
        assembly {
            sstore(BEACON_SLOT, _beacon)
        }
    }

    function implementation() public view returns (address) {
        return IBeacon(getBeacon()).implementation();
    }

    function getBeacon() public view returns (address) {
        address beacon;
        assembly {
            let beacon := sload(BEACON_SLOT)
        }
        return beacon;
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external payable {
        address implementation = implementation();

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