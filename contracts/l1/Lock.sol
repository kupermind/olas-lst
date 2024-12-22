// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Treasury} from "./Treasury.sol";

interface IToken {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

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

interface IVEOLAS {
    struct LockedBalance {
        // Token amount. It will never practically be bigger. Initial OLAS cap is 1 bn tokens, or 1e27.
        // After 10 years, the inflation rate is 2% per year. It would take 1340+ years to reach 2^128 - 1
        uint128 amount;
        // Unlock time. It will never practically be bigger
        uint64 endTime;
    }

    /// @dev Deposits `amount` tokens for `msg.sender` and locks for `unlockTime`.
    /// @param amount Amount to deposit.
    /// @param unlockTime Time when tokens unlock, rounded down to a whole week.
    function createLock(uint256 amount, uint256 unlockTime) external;

    /// @dev Deposits `amount` additional tokens for `msg.sender` without modifying the unlock time.
    /// @param amount Amount of tokens to deposit and add to the lock.
    function increaseAmount(uint256 amount) external;

    /// @dev Extends the unlock time.
    /// @param unlockTime New tokens unlock time.
    function increaseUnlockTime(uint256 unlockTime) external;

    /// @dev Withdraws all tokens for `msg.sender`. Only possible if the lock has expired.
    function withdraw() external;

    function mapLockedBalances(address account) external returns (LockedBalance memory);
}

/// @dev Zero address.
error ZeroAddress();

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Only `treasury` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param treasury Required treasury address.
error TreasuryOnly(address sender, address treasury);

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @title Lock - Smart contract for veOLAS related lock and voting functions
contract Lock {
    // Maximum veOLAS lock time (4 years)
    uint256 public constant MAX_LOCK_TIME = 4 * 365 * 1 days;

    // veOLAS address
    address public immutable ve;
    // OLAS address
    address public immutable olas;
    // Treasury address
    address public immutable treasury;

    // Governor address
    address public governor;
    // Owner address
    address public owner;

    /// @dev Lock constructor.
    /// @param _olas OLAS address.
    /// @param _ve veOLAS address.
    /// @param _treasury Treasury address.
    constructor(address _olas, address _ve, address _treasury) {
        // Check for the zero address
        if (_olas == address(0) || _ve == address(0) || _treasury == address(0)) {
            revert ZeroAddress();
        }

        ve = _ve;
        olas = _olas;
        treasury = _treasury;
    }

    /// @dev Lock initializer.
    function initialize(address _governor) external{
        // Check for already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        owner = msg.sender;
        governor = _governor;
    }

    function createFirstLock(uint256 olasAmount) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get OLAS from owner
        IToken(olas).transferFrom(msg.sender, address(this), olasAmount);
        // Approve OLAS for veOLAS
        IToken(olas).approve(ve, olasAmount);
        // Create lock
        IVEOLAS(ve).createLock(olasAmount, MAX_LOCK_TIME);
    }

    function increaseLock(uint256 olasAmount) external {
        // Check for ownership
        if (msg.sender != treasury) {
            revert TreasuryOnly(msg.sender, treasury);
        }

        // Get OLAS from treasury
        IToken(olas).transferFrom(msg.sender, address(this), olasAmount);

        // Approve OLAS for veOLAS
        IToken(olas).approve(ve, olasAmount);

        // Increase amount and unlock time to a maximum
        IVEOLAS(ve).increaseAmount(olasAmount);
        IVEOLAS(ve).increaseUnlockTime(MAX_LOCK_TIME);
    }

    function unlock(address account, uint256 amount) external {
        /// TBD
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // TODO Never withdraw the full amount, i.e. neve close the treasury lock
        LockedBalance memory lockedBalance = IVEOLAS(ve).mapLockedBalances(address(this));

        // Withdraw veOLAS
        IVEOLAS(ve).withdraw();

        // TODO For testing purposes now
        // Transfer OLAS
        IToken(olas).transfer(treasury, amount);
    }

    function castVote(uint256 proposalId, uint8 vote) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        IGovernor(governor).castVote(proposalId, vote);
    }
}
