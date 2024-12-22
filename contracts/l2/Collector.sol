// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Zero address.
error ZeroAddress();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @title Collector - Smart contract for collecting staking rewards
contract Collector {
    event ActivityIncreased(uint256 activityChange);

    // Max protocol factor
    uint256 public constant MAX_PROTOCOL_FACTOR = 10_000;

    // Protocol balance
    uint256 public protocolBalance;
    // Protocol factor in 10_000 value
    uint256 public protocolFactor;
    // L2 staking processor address
    address public l2StakingProcessor;
    // Owner address
    address public owner;

    constructor(address _l2StakingProcessor) {
        l2StakingProcessor = _l2StakingProcessor;
    }

    function initialize(uint256 _protocolFactor) external {
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        protocolFactor = _protocolFactor;
        owner = msg.sender;
    }

    /// @dev Changes protocol factor value.
    /// @param newProtocolFactor New lock factor value.
    function changeLockFactor(address newProtocolFactor) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (protocolFactor == 0) {
            revert ZeroValue();
        }

        protocolFactor = newProtocolFactor;
        emit LockFactorUpdated(newProtocolFactor);
    }
    
    // TODO service to post info about incoming transfers on L1?
    function relayTokens() external payable {
        // Get OLAS balance
        uint256 olasBalance = IToken(olas).balanceOf(address(this));
        // Get current protocol balance
        uint256 curProtocolBalance = protocolBalance;

        uint256 amount = olasBalance - curProtocolBalance;
        // Minimum balance is 1 OLAS
        if (amount < 1 ether) {
            revert ZeroValue();
        }

        uint256 protocolAmount = (balance * protocolFactor) / MAX_PROTOCOL_FACTOR;
        amount -= protocolAmount;

        // Update protocol balance
        curProtocolBalance += protocolAmount;
        protocolBalance = curProtocolBalance;

        // Approve tokens
        IToken(olas).approve(l2StakingProcessor, amount);

        IBridge(l2StakingProcessor).relayToL1{value: msg.value}(amount);
    }
}
