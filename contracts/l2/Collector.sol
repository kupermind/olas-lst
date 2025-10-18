// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Implementation, OwnerOnly, ZeroAddress} from "../Implementation.sol";

interface IBridge {
    function relayToL1(address to, uint256 olasAmount, bytes memory bridgePayload) external payable;
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

/// @dev Wrong length of arrays.
error WrongArrayLength();

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

// ReceiverBalance struct
struct ReceiverBalance {
    uint256 balance;
    address receiver;
}

/// @title Collector - Smart contract for collecting staking rewards
contract Collector is Implementation {
    event StakingProcessorUpdated(address indexed stakingProcessorL2);
    event OperationReceiversSet(bytes32[] operations, address[] receivers);
    event OperationReceiverBalancesUpdated(bytes32 indexed operation, address indexed receiver, uint256 balance);
    event ProtocolFactorUpdated(uint256 protocolFactor);
    event ProtocolBalanceUpdated(uint256 protocolBalance);
    event TokensRelayed(address indexed l1Distributor, uint256 amount);

    // Reward transfer operation
    bytes32 public constant REWARD = 0x0b9821ae606ebc7c79bf3390bdd3dc93e1b4a7cda27aad60646e7b88ff55b001;
    // Min olas balance to relay
    uint256 public constant MIN_OLAS_BALANCE = 1 ether;
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

    // Reentrancy lock
    uint256 internal _locked = 1;

    // Mapping of operation => OLAS balance and L1 address to send to
    mapping(bytes32 => ReceiverBalance) public mapOperationReceiverBalances;

    /// @param _olas OLAS address on L2.
    constructor(address _olas) {
        olas = _olas;
    }

    /// @dev Initializes collector.
    function initialize() external {
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        owner = msg.sender;
    }

    /// @dev Changes staking processor L2 address.
    /// @param newStakingProcessorL2 New staking processor L2 address.
    function changeStakingProcessorL2(address newStakingProcessorL2) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (newStakingProcessorL2 == address(0)) {
            revert ZeroAddress();
        }

        l2StakingProcessor = newStakingProcessorL2;
        emit StakingProcessorUpdated(newStakingProcessorL2);
    }

    /// @dev Changes protocol factor value.
    /// @param newProtocolFactor New protocol factor value.
    function changeProtocolFactor(uint256 newProtocolFactor) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        protocolFactor = newProtocolFactor;
        emit ProtocolFactorUpdated(newProtocolFactor);
    }

    /// @dev Sets receiver addresses according operation type.
    /// @param operations Operation types.
    /// @param receivers Corresponding receiver addresses.
    function setOperationReceivers(bytes32[] memory operations, address[] memory receivers) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check array lengths
        if (operations.length == 0 || operations.length != receivers.length) {
            revert WrongArrayLength();
        }

        for (uint256 i = 0; i < operations.length; ++i) {
            // Check for zero value
            if (operations[i] == 0) {
                revert ZeroValue();
            }

            // Check for zero address
            if (receivers[i] == address(0)) {
                revert ZeroAddress();
            }

            ReceiverBalance storage receiverBalance = mapOperationReceiverBalances[operations[i]];
            receiverBalance.receiver = receivers[i];
        }

        emit OperationReceiversSet(operations, receivers);
    }

    /// @dev Tops up address(this) with a specified amount according to a selected operation.
    /// @param amount OLAS amount.
    /// @param operation Operation type.
    function topUpBalance(uint256 amount, bytes32 operation) external {
        // Reentrancy guard
        if (_locked == 2) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get ReceiverBalance struct according to the operation type
        ReceiverBalance storage receiverBalance = mapOperationReceiverBalances[operation];

        // Get receiver address
        address receiver = receiverBalance.receiver;
        // Check for zero address
        if (receiverBalance.receiver == address(0)) {
            revert ZeroAddress();
        }

        // Pull OLAS amount and increase corresponding balance
        IToken(olas).transferFrom(msg.sender, address(this), amount);
        uint256 balance = receiverBalance.balance + amount;
        receiverBalance.balance = balance;

        emit OperationReceiverBalancesUpdated(operation, receiver, balance);

        _locked = 1;
    }

    /// @dev Relays tokens to L1.
    /// @param operation Operation type related to L1 receiver.
    /// @param bridgePayload Bridge payload.
    function relayTokens(bytes32 operation, bytes memory bridgePayload) external payable {
        // Reentrancy guard
        if (_locked == 2) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get ReceiverBalance struct according to the operation type
        ReceiverBalance storage receiverBalance = mapOperationReceiverBalances[operation];

        // Get receiver address
        address receiver = receiverBalance.receiver;
        // Check for zero address
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        // Get OLAS balance
        uint256 olasBalance = receiverBalance.balance;
        // Check for minimum balance
        if (olasBalance < MIN_OLAS_BALANCE) {
            revert ZeroValue();
        }

        // Rewards are subject to a protocol fee, if applicable
        if (operation == REWARD) {
            uint256 curProtocolFactor = protocolFactor;

            if (curProtocolFactor > 0) {
                uint256 protocolAmount = (olasBalance * protocolFactor) / MAX_PROTOCOL_FACTOR;
                olasBalance -= protocolAmount;

                // Update protocol balance
                uint256 curProtocolBalance = protocolBalance + protocolAmount;
                protocolBalance = curProtocolBalance;

                emit ProtocolBalanceUpdated(curProtocolBalance);
            }
        }

        // Zero operation balance
        receiverBalance.balance = 0;

        emit TokensRelayed(receiver, olasBalance);

        // Transfer tokens
        IToken(olas).transfer(l2StakingProcessor, olasBalance);

        // Send tokens to L1
        IBridge(l2StakingProcessor).relayToL1{value: msg.value}(receiver, olasBalance, bridgePayload);

        _locked = 1;
    }

    function fundExternal(address account, uint256 amount) external {
        // Reentrancy guard
        if (_locked == 2) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get current protocol balance
        uint256 curProtocolBalance = protocolBalance;

        // Check for overflow
        if (amount > curProtocolBalance) {
            revert Overflow(amount, curProtocolBalance);
        }

        // Update protocol balance
        curProtocolBalance -= amount;
        protocolBalance = curProtocolBalance;

        // Transfer tokens
        IToken(olas).transfer(account, amount);

        emit ProtocolBalanceUpdated(curProtocolBalance);

        _locked = 1;
    }
}
