// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockVE {
    mapping(address => uint256) private _votes;
    
    constructor(address _token) {}
    
    function getVotes(address account) external view returns (uint256) {
        return _votes[account];
    }
    
    function setVotes(address account, uint256 amount) external {
        _votes[account] = amount;
    }
}
