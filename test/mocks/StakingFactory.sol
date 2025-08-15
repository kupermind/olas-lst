// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract StakingFactory {
    address public stakingVerifier;
    
    constructor(address _stakingVerifier) {
        stakingVerifier = _stakingVerifier;
    }
    
    function createStakingInstance(address implementation, bytes memory initPayload) external returns (address) {
        // Deploy a new proxy contract
        bytes memory bytecode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        
        address stakingInstance;
        assembly {
            stakingInstance := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        
        // Initialize the contract
        (bool success,) = stakingInstance.call(initPayload);
        require(success, "Initialization failed");
        
        return stakingInstance;
    }
}
