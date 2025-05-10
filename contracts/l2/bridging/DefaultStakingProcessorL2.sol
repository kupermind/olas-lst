// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IBridgeErrors} from "../../interfaces/IBridgeErrors.sol";

// StakingManager interface
interface IStakingManager {
    function stake(address stakingProxy, uint256 amount) external;

    /// @dev Unstakes, if needed, and withdraws specified amounts from a specified staking contract.
    /// @notice Unstakes services if needed to satisfy withdraw requests.
    ///         Call this to unstake definitely terminated staking contracts - deactivated on L1 and / or ran out of funds.
    ///         The majority of discovered chains does not need any value to process token bridge transfer.
    function unstake(address stakingProxy, uint256 amount) external;
}

// Necessary ERC20 token interface
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

    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);
}

/// @title DefaultStakingProcessorL2 - Smart contract for processing tokens and data received on L2, and tokens sent back to L1.
abstract contract DefaultStakingProcessorL2 is IBridgeErrors {
    event OwnerUpdated(address indexed owner);
    event FundsReceived(address indexed sender, uint256 value);
    event StakeRequestExecuted(address target, uint256 amount, bytes32 indexed batchHash);
    event StakeRequestQueued(bytes32 indexed queueHash, address target, uint256 amount,
        bytes32 indexed batchHash, bytes32 operation, uint256 olasBalance, uint256 paused);
    event UnstakeRequestQueued(bytes32 indexed queueHash, address target, uint256 amount,
        bytes32 indexed batchHash, bytes32 operation, uint256 paused);
    event MessageReceived(address indexed sender, uint256 chainId, bytes data);
    event Drain(address indexed owner, uint256 amount);
    event Migrated(address indexed sender, address indexed newL2TargetDispenser, uint256 amount);
    event StakingProcessorPaused();
    event StakingProcessorUnpaused();

    // Maximum chain Id as per EVM specs
    uint256 public constant MAX_CHAIN_ID = type(uint64).max / 2 - 36;
    // Stake operation
    bytes32 public constant STAKE = 0x1bcc0f4c3fad314e585165815f94ecca9b96690a26d6417d7876448a9a867a69;
    // Unstake operation
    bytes32 public constant UNSTAKE = 0x8ca9a95e41b5eece253c93f5b31eed1253aed6b145d8a6e14d913fdf8e732293;

    // OLAS address
    address public immutable olas;
    // Staking manager address
    address public immutable stakingManager;
    // L2 Relayer address that receives the message across the bridge from the source L1 network
    address public immutable l2MessageRelayer;
    // L2 Token relayer address that sends tokens to the L1 source network
    address public immutable l2TokenRelayer;
    // Deposit processor address on L1 that is authorized to propagate the transaction execution across the bridge
    address public immutable l1DepositProcessor;
    // Deposit processor chain Id
    uint256 public immutable l1SourceChainId;
    // Owner address (Timelock or bridge mediator)
    address public owner;
    // Pause switcher
    uint8 public paused;
    // Reentrancy lock
    uint256 internal _locked;

    // Processed batch hashes
    mapping(bytes32 => bool) public processedHashes;
    // Queued hashes of (target, amount, batchHash)
    mapping(bytes32 => bool) public queuedHashes;

    /// @dev DefaultStakerL2 constructor.
    /// @param _olas OLAS token address on L2.
    /// @param _stakingManager StakingManager address.
    /// @param _l2TokenRelayer L2 token relayer bridging contract address.
    /// @param _l2MessageRelayer L2 message relayer bridging contract address.
    /// @param _l1SourceChainId L1 source chain Id.
    constructor(
        address _olas,
        address _stakingManager,
        address _l2TokenRelayer,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId
    ) {
        // Check for zero addresses
        if (_olas == address(0) || _stakingManager == address(0) || _l2TokenRelayer == address(0) ||
            _l2MessageRelayer == address(0) || _l1DepositProcessor == address(0)) {
            revert ZeroAddress();
        }

        // Check for a zero value
        if (_l1SourceChainId == 0) {
            revert ZeroValue();
        }

        // Check for overflow value
        if (_l1SourceChainId > MAX_CHAIN_ID) {
            revert Overflow(_l1SourceChainId, MAX_CHAIN_ID);
        }

        // Immutable parameters assignment
        olas = _olas;
        stakingManager = _stakingManager;
        l2TokenRelayer = _l2TokenRelayer;
        l2MessageRelayer = _l2MessageRelayer;
        l1DepositProcessor = _l1DepositProcessor;
        l1SourceChainId = _l1SourceChainId;

        // State variables assignment
        owner = msg.sender;
        paused = 1;
        _locked = 1;
    }

    /// @dev Processes the data received from L1.
    /// @param data Bytes message data sent from L1.
    function _processData(bytes memory data) internal {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Decode received data
        (address target, uint256 amount, bytes32 batchHash, bytes32 operation) =
            abi.decode(data, (address, uint256, bytes32, bytes32));

        // Check that the batch hash has not yet being processed
        // Possible scenario: bridge failed to deliver from L1 to L2, maintenance function is called by the DAO,
        // and the bridge somehow re-delivers the same message that has already been processed
        if (processedHashes[batchHash]) {
            revert AlreadyDelivered(batchHash);
        }
        processedHashes[batchHash] = true;

        if (operation == STAKE) {
            // Get current OLAS balance
            uint256 olasBalance = IToken(olas).balanceOf(address(this));

            bool success;

            // Check the OLAS balance and the contract being unpaused
            if (olasBalance >= amount && paused == 1) {
                // Approve OLAS for stakingManager
                IToken(olas).approve(stakingManager, amount);

                // This is a low level call since it must never revert
                bytes memory stakeData = abi.encodeCall(IStakingManager.stake, (target, amount));
                (success, ) = stakingManager.call(stakeData);
                //IStakingManager(stakingManager).stake(target, amount);

                if (success) {
                    emit StakeRequestExecuted(target, amount, batchHash);
                }
            }

            // If anything went wrong, queue the staking request
            if (!success) {
                // Hash of target + amount + batchHash + operation + current target dispenser address (migration-proof)
                bytes32 queueHash =
                    keccak256(abi.encode(target, amount, batchHash, operation, block.chainid, address(this)));
                // Queue the hash for further redeem
                queuedHashes[queueHash] = true;

                emit StakeRequestQueued(queueHash, target, amount, batchHash, operation, olasBalance, paused);
            }
        } else if (operation == UNSTAKE) {
            // This is a low level call since it must never revert
            bytes memory unstakeData = abi.encodeCall(IStakingManager.unstake, (target, amount));
            (bool success, ) = stakingManager.call(unstakeData);

            if (!success) {
                // Hash of target + amount + batchHash + operation + current target dispenser address (migration-proof)
                bytes32 queueHash =
                    keccak256(abi.encode(target, amount, batchHash, operation, block.chainid, address(this)));
                // Queue the hash for further redeem
                queuedHashes[queueHash] = true;

                emit UnstakeRequestQueued(queueHash, target, amount, batchHash, operation, paused);
            }
        } else {
            // This must never happen
            revert OperationNotFound(operation);
        }

        _locked = 1;
    }

    /// @dev Receives a message from L1.
    /// @param messageRelayer L2 bridge message relayer address.
    /// @param sourceProcessor L1 deposit processor address.
    /// @param data Bytes message data sent from L1.
    function _receiveMessage(
        address messageRelayer,
        address sourceProcessor,
        bytes memory data
    ) internal virtual {
        // Check L2 message relayer address
        if (messageRelayer != l2MessageRelayer) {
            revert TargetRelayerOnly(messageRelayer, l2MessageRelayer);
        }

        // Check L1 deposit processor address
        if (sourceProcessor != l1DepositProcessor) {
            revert WrongMessageSender(sourceProcessor, l1DepositProcessor);
        }

        emit MessageReceived(l1DepositProcessor, l1SourceChainId, data);

        // Process the data
        _processData(data);
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Redeems queued staking deposit / withdraw.
    /// @param target Staking target address.
    /// @param amount Staking amount.
    /// @param batchHash Batch hash.
    /// @param operation Funds operation: stake / unstake.
    function redeem(address target, uint256 amount, bytes32 batchHash, bytes32 operation) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Pause check
        if (paused == 2) {
            revert Paused();
        }

        // Hash of target + amount + batchHash + operation + chainId + current target dispenser address (migration-proof)
        bytes32 queueHash = keccak256(abi.encode(target, amount, batchHash, operation, block.chainid, address(this)));
        bool queued = queuedHashes[queueHash];
        // Check if the target and amount are queued
        if (!queued) {
            revert TargetAmountNotQueued(target, amount, batchHash, operation);
        }

        if (operation == STAKE) {
            // Get the current contract OLAS balance
            uint256 olasBalance = IToken(olas).balanceOf(address(this));
            if (olasBalance >= amount) {
                // Approve OLAS for stakingManager
                IToken(olas).approve(stakingManager, amount);
                IStakingManager(stakingManager).stake(target, amount);

                emit StakeRequestExecuted(target, amount, batchHash);

                // Remove processed queued nonce
                queuedHashes[queueHash] = false;
            } else {
                // OLAS balance is not enough for redeem
                revert InsufficientBalance(olasBalance, amount);
            }
        } else if (operation == UNSTAKE) {
            IStakingManager(stakingManager).unstake(target, amount);
        } else {
            // Must never happen
            revert OperationNotFound(operation);
        }

        _locked = 1;
    }

    /// @dev Processes the data manually provided by the DAO in order to restore the data that was not delivered from L1.
    /// @notice All the staking target addresses encoded in the data must follow the undelivered ones, and thus be unique.
    ///         The data payload here must correspond to the exact data failed to be delivered (targets, incentives, batch).
    ///         Here are possible bridge failure scenarios and the way to act via the DAO vote:
    ///         - Both token and message delivery fails: re-send OLAS to the contract (separate vote), call this function;
    ///         - Token transfer succeeds, message fails: call this function;
    ///         - Token transfer fails, message succeeds: re-send OLAS to the contract (separate vote).
    /// @param data Bytes message data that was not delivered from L1.
    function processDataMaintenance(bytes memory data) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Process the data
        _processData(data);
    }

    /// @dev Pause the contract.
    function pause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 2;
        emit StakingProcessorPaused();
    }

    /// @dev Unpause the contract
    function unpause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 1;
        emit StakingProcessorUnpaused();
    }

    /// @dev Drains contract native funds.
    /// @notice For cross-bridge leftovers and incorrectly sent funds.
    /// @return amount Drained amount to the owner address.
    function drain() external returns (uint256 amount) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the owner address
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Drain the slashed funds
        amount = address(this).balance;
        if (amount == 0) {
            revert ZeroValue();
        }

        // Send funds to the owner
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) {
            revert TransferFailed(address(0), address(this), msg.sender, amount);
        }

        emit Drain(msg.sender, amount);

        _locked = 1;
    }

    /// @dev Migrates funds to a new specified L2 target dispenser contract address.
    /// @notice The contract must be paused to prevent other interactions.
    ///         The owner is be zeroed, the contract becomes paused and in the reentrancy state for good.
    ///         No further write interaction with the contract is going to be possible.
    ///         If the withheld amount is nonzero, it is regulated by the DAO directly on the L1 side.
    ///         If there are outstanding queued requests, they are processed by the DAO directly on the L2 side.
    function migrate(address newL2TargetDispenser) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the owner address
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check that the contract is paused
        if (paused == 1) {
            revert Unpaused();
        }

        // Check that the migration address is a contract
        if (newL2TargetDispenser.code.length == 0) {
            revert WrongAccount(newL2TargetDispenser);
        }

        // Check that the new address is not the current one
        if (newL2TargetDispenser == address(this)) {
            revert WrongAccount(address(this));
        }

        // Get OLAS token amount
        uint256 amount = IToken(olas).balanceOf(address(this));
        // Transfer amount to the new L2 target dispenser
        if (amount > 0) {
            bool success = IToken(olas).transfer(newL2TargetDispenser, amount);
            if (!success) {
                revert TransferFailed(olas, address(this), newL2TargetDispenser, amount);
            }
        }

        // Zero the owner
        owner = address(0);

        emit Migrated(msg.sender, newL2TargetDispenser, amount);

        // _locked is now set to 2 for good
    }

    /// @dev Relays OLAS to L1.
    /// @param to Address to send tokens to.
    /// @param olasAmount OLAS amount.
    /// @param bridgePayload Bridge payload.
    function relayToL1(address to, uint256 olasAmount, bytes memory bridgePayload) external virtual payable;

    /// @dev Gets the maximum number of token decimals able to be transferred across the bridge.
    /// @return Number of supported decimals.
    function getBridgingDecimals() public pure virtual returns (uint256) {
        return 18;
    }

    /// @dev Receives native network token.
    receive() external payable {
        // Disable receiving native funds after the contract has been migrated
        if (owner == address(0)) {
            revert TransferFailed(address(0), msg.sender, address(this), msg.value);
        }

        emit FundsReceived(msg.sender, msg.value);
    }
}