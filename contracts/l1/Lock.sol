// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Implementation, OwnerOnly, ZeroAddress} from "../Implementation.sol";
import {Treasury} from "./Treasury.sol";

interface IGovernor {
    /// @dev Create a new proposal to change the protocol / contract parameters.
    /// @param targets The ordered list of target addresses for calls to be made during proposal execution.
    /// @param values The ordered list of values to be passed to the calls made during proposal execution.
    /// @param calldatas The ordered list of data to be passed to each individual function call during proposal execution.
    /// @param description A human readable description of the proposal and the changes it will enact.
    /// @return The Id of the newly created proposal.
    function propose(address[] memory targets, uint256[] memory values, bytes[] memory calldatas,
        string memory description) external returns (uint256);

    /// @dev Casts a vote
    function castVote(uint256 proposalId, uint8 support) external returns (uint256);
}

interface IToken {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);

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

/// @dev Zero value.
error ZeroValue();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @title Lock - Smart contract for veOLAS related lock and voting functions
contract Lock is Implementation {
    event OlasGovernorUpdated(address indexed olasGovernor);

    // Maximum veOLAS lock time (4 years)
    uint256 public constant MAX_LOCK_TIME = 4 * 365 * 1 days;

    // veOLAS address
    address public immutable ve;
    // OLAS address
    address public immutable olas;

    // OLAS olasGovernor address
    address public olasGovernor;

    /// @dev Lock constructor.
    /// @param _olas OLAS address.
    /// @param _ve veOLAS address.
    constructor(address _olas, address _ve) {
        // Check for zero addresses
        if (_olas == address(0) || _ve == address(0)) {
            revert ZeroAddress();
        }

        ve = _ve;
        olas = _olas;
    }

    /// @dev Lock initializer.
    function initialize() external{
        // Check for already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        owner = msg.sender;
    }
    
    /// @dev Changes OLAS governor address.
    /// @param newOlasGovernor New OLAS governor address.
    function changeGovernor(address newOlasGovernor) external{
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (newOlasGovernor == address(0)) {
            revert ZeroAddress();
        }
        
        olasGovernor = newOlasGovernor;
        emit OlasGovernorUpdated(newOlasGovernor);
    }

    /// @dev Sets OLAS governor address and creates first veOLAS lock.
    /// @param _olasGovernor OLAS governor address.
    function setGovernorAndCreateFirstLock(address _olasGovernor) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (_olasGovernor == address(0)) {
            revert ZeroAddress();
        }

        // Deposit starting OLAS amount
        uint256 olasAmount = IToken(olas).balanceOf(address(this));
        // Check for zero value
        if (olasAmount == 0) {
            revert ZeroValue();
        }

        // Approve OLAS for veOLAS
        IToken(olas).approve(ve, olasAmount);
        // Create lock
        IVEOLAS(ve).createLock(olasAmount, MAX_LOCK_TIME);

        olasGovernor = _olasGovernor;
        emit OlasGovernorUpdated(_olasGovernor);
    }

    // TODO lock full balance and make this ownerless?
    /// @dev Increases lock amount and time.
    /// @param olasAmount OLAS amount.
    function increaseLock(uint256 olasAmount) external {
        // Approve OLAS for veOLAS
        IToken(olas).approve(ve, olasAmount);

        // Increase lock amount
        IVEOLAS(ve).increaseAmount(olasAmount);
        // Increase unlock time to a maximum, if possible
        bytes memory increaseUnlockTimeData = abi.encodeCall(IVEOLAS.increaseUnlockTime, (MAX_LOCK_TIME));
        ve.call(increaseUnlockTimeData);
    }

    function unlock(address account, uint256 amount) external {
        /// TBD
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // TODO Never withdraw the full amount, i.e. neve close the treasury lock
        IVEOLAS.LockedBalance memory lockedBalance = IVEOLAS(ve).mapLockedBalances(address(this));

        // Withdraw veOLAS
        IVEOLAS(ve).withdraw();

        // TODO For testing purposes now
        // Transfer OLAS
        IToken(olas).transfer(account, amount);
    }

    /// @dev Create a new proposal to change the protocol / contract parameters.
    /// @param targets The ordered list of target addresses for calls to be made during proposal execution.
    /// @param values The ordered list of values to be passed to the calls made during proposal execution.
    /// @param calldatas The ordered list of data to be passed to each individual function call during proposal execution.
    /// @param description A human readable description of the proposal and the changes it will enact.
    /// @return The Id of the newly created proposal.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256){
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        return IGovernor(olasGovernor).propose(targets, values, calldatas, description);
    }

    /// @dev Casts a vote.
    /// @param proposalId Proposal Id.
    /// @param support Support value: against, for, abstain.
    /// @return Vote weight.
    function castVote(uint256 proposalId, uint8 support) external returns (uint256) {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        return IGovernor(olasGovernor).castVote(proposalId, support);
    }
}
