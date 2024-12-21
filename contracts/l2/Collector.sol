// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Zero address.
error ZeroAddress();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @title Collector - Smart contract for collecting staking rewards
contract Collector {
    event ActivityIncreased(uint256 activityChange);

    // L2 staking processor address
    address public l2StakingProcessor;
    // Owner address
    address public owner;

    constructor(address _l2StakingProcessor) {
        l2StakingProcessor = _l2StakingProcessor;
    }

    function initialize() external {
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        owner = msg.sender;
    }

    // TODO service to post info about incoming transfers on L1?
    function relayTokens(uint256 amount) external payable {
        // Get OLAS balance
        uint256 balance = IToken(olas).balanceOf(address(this));

        if (amount == 0 || amount > balance) {
            amount = balance;
        }

        if (amount == 0) {
            revert ZeroValue();
        }

        // Send tokens
        IToken(olas).approve(l2StakingProcessor, amount);

        IBridge(l2StakingProcessor).relayToL1{value: msg.value}(amount);
    }
}
