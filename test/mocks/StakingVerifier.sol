// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract StakingVerifier {
    mapping(address => bool) public implementationsStatuses;

    constructor(
        address _token,
        address _serviceRegistry,
        address _serviceRegistryTokenUtility,
        uint256 _minStakingDeposit,
        uint256 _timeForEmissions,
        uint256 _maxNumServices,
        uint256 _apyLimit
    ) {}

    function setImplementationsStatuses(address[] memory implementations, bool[] memory statuses, bool isWhitelist)
        external
    {
        for (uint256 i = 0; i < implementations.length; i++) {
            implementationsStatuses[implementations[i]] = statuses[i];
        }
    }
}
