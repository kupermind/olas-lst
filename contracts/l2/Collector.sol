// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Implementation, OwnerOnly, ZeroAddress} from "../Implementation.sol";

interface IBridge {
    function relayToL1(address to, uint256 olasAmount) external payable;
}

// ERC20 token interface
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

    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);
}

/// @dev Zero value.
error ZeroValue();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @title Collector - Smart contract for collecting staking rewards
contract Collector is Implementation {
    event ProtocolFactorUpdated(uint256 protocolFactor);
    event ActivityIncreased(uint256 activityChange);

    // TODO adjust
    // Min olas balance to relay
    uint256 public constant MIN_OLAS_BALANCE = 1;// ether;
    // Max protocol factor
    uint256 public constant MAX_PROTOCOL_FACTOR = 10_000;

    // OLAS contract address
    address public immutable olas;
    // stOLAS contract address on L1
    address public immutable l1St;

    // Protocol balance
    uint256 public protocolBalance;
    // Protocol factor in 10_000 value
    uint256 public protocolFactor;
    // L2 staking processor address
    address public l2StakingProcessor;

    /// @param _olas OLAS address on L2.
    /// @param _l1St stOLAS address on L1.
    constructor(address _olas, address _l1St) {
        olas = _olas;
        l1St = _l1St;
    }

    /// @dev Initializes collector.
    function initialize() external {
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        owner = msg.sender;
    }

    function changeStakingProcessorL2(address newStakingProcessorL2) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (newStakingProcessorL2 == address(0)) {
            revert ZeroAddress();
        }

        l2StakingProcessor = newStakingProcessorL2;
    }

    /// @dev Changes protocol factor value.
    /// @param newProtocolFactor New lock factor value.
    function changeProtocolFactor(uint256 newProtocolFactor) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero value
        if (protocolFactor == 0) {
            revert ZeroValue();
        }

        protocolFactor = newProtocolFactor;
        emit ProtocolFactorUpdated(newProtocolFactor);
    }

    // TODO Add bridgePayload
    function relayRewardTokens() external payable {
        // Get OLAS balance
        uint256 olasBalance = IToken(olas).balanceOf(address(this));
        // Get current protocol balance
        uint256 curProtocolBalance = protocolBalance;

        // Overflow check: this must never happen, as protocol balance is included in total OLAS balance
        if (olasBalance < curProtocolBalance) {
            revert Overflow(olasBalance, curProtocolBalance);
        }

        uint256 amount = olasBalance - curProtocolBalance;
        // Check for minimum balance
        if (amount < MIN_OLAS_BALANCE) {
            revert ZeroValue();
        }

        uint256 protocolAmount = (olasBalance * protocolFactor) / MAX_PROTOCOL_FACTOR;
        amount -= protocolAmount;

        // Update protocol balance
        curProtocolBalance += protocolAmount;
        protocolBalance = curProtocolBalance;

        // Transfer tokens
        IToken(olas).transfer(l2StakingProcessor, amount);

        // TODO Check on relays, but the majority of them does not require value
        // TODO: Make sure once again no value is needed to send tokens back
        // Send tokens to L1
        IBridge(l2StakingProcessor).relayToL1{value: msg.value}(l1St, amount);
    }

    // TODO withdraw
}
