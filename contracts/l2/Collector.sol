// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IBridge {
    function relayToL1(uint256 olasAmount) external payable;
}

// ERC20 token interface
interface IToken {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero value.
error ZeroValue();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @title Collector - Smart contract for collecting staking rewards
contract Collector {
    event ProtocolFactorUpdated(uint256 protocolFactor);
    event ActivityIncreased(uint256 activityChange);

    // Max protocol factor
    uint256 public constant MAX_PROTOCOL_FACTOR = 10_000;

    // OLAS contract address
    address public immutable olas;

    // Protocol balance
    uint256 public protocolBalance;
    // Protocol factor in 10_000 value
    uint256 public protocolFactor;
    // L2 staking processor address
    address public l2StakingProcessor;
    // Owner address
    address public owner;

    constructor(address _olas, address _l2StakingProcessor) {
        olas = _olas;
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
    function changeLockFactor(uint256 newProtocolFactor) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (protocolFactor == 0) {
            revert ZeroValue();
        }

        protocolFactor = newProtocolFactor;
        emit ProtocolFactorUpdated(newProtocolFactor);
    }
    
    // TODO service to post info about incoming transfers on L1?
    function relayTokens() external payable {
        // Get OLAS balance
        uint256 olasBalance = IToken(olas).balanceOf(address(this));
        // Get current protocol balance
        uint256 curProtocolBalance = protocolBalance;

        // TODO overflow check
        uint256 amount = olasBalance - curProtocolBalance;
        // Minimum balance is 1 OLAS
        if (amount < 1 ether) {
            revert ZeroValue();
        }

        uint256 protocolAmount = (olasBalance * protocolFactor) / MAX_PROTOCOL_FACTOR;
        amount -= protocolAmount;

        // Update protocol balance
        curProtocolBalance += protocolAmount;
        protocolBalance = curProtocolBalance;

        // Approve tokens
        IToken(olas).approve(l2StakingProcessor, amount);

        IBridge(l2StakingProcessor).relayToL1{value: msg.value}(amount);
    }
}
