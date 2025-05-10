// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IToken {
    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @dev Mocking contract of voting escrow.
contract MockVE {
    address public immutable olas;

    uint256 public balance = 50 ether;
    uint256 public supply = 100 ether;
    uint256 public weightedBalance = 10_000 ether;
    mapping(address => uint256) public accountWeightedBalances;
    mapping(address => uint256) public accountLockTimes;

    constructor(address _olas) {
        olas = _olas;
    }

    /// @dev Simulates a lock for the specified account.
    function createLock(uint256 amount, uint256) external {
        IToken(olas).transferFrom(msg.sender, address(this), amount);
        accountWeightedBalances[msg.sender] = amount;
    }

    /// @dev Deposits `amount` additional tokens for `msg.sender` without modifying the unlock time.
    /// @param amount Amount of tokens to deposit and add to the lock.
    function increaseAmount(uint256 amount) external {
        IToken(olas).transferFrom(msg.sender, address(this), amount);
        accountWeightedBalances[msg.sender] = amount;
    }

    /// @dev Extends the unlock time.
    /// @param unlockTime New tokens unlock time.
    function increaseUnlockTime(uint256 unlockTime) external {
        accountLockTimes[msg.sender] = unlockTime;
    }

    /// @dev Simulates a lock for the specified account.
    function withdraw() external {
        uint256 amount = accountWeightedBalances[msg.sender];
        accountWeightedBalances[msg.sender] = 0;
        IToken(olas).transfer(msg.sender, amount);
    }

    /// @dev Gets the account balance at a specific block number.
    function balanceOfAt(address, uint256) external view returns (uint256){
        return balance;
    }

    /// @dev Gets total token supply at a specific block number.
    function totalSupplyAt(uint256) external view returns (uint256) {
        return supply;
    }

    /// @dev Gets weighted account balance.
    function getVotes(address account) external view returns (uint256) {
        return accountWeightedBalances[account];
    }

    /// @dev Sets the new balance.
    function setBalance(uint256 newBalance) external {
        balance = newBalance;
    }

    /// @dev Sets the new total supply.
    function setSupply(uint256 newSupply) external {
        supply = newSupply;
    }

    /// @dev Sets the new weighted balance.
    function setWeightedBalance(uint256 newWeightedBalance) external {
        weightedBalance = newWeightedBalance;
    }
}
