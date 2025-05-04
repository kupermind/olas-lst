// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IStaking} from "../interfaces/IStaking.sol";

interface ISafe {
    enum Operation {Call, DelegateCall}

    function nonce() external returns (uint256);

    /// @dev Marks a hash as approved. This can be used to validate a hash that is used by a signature.
    ///  @param hashToApprove The hash that should be marked as approved for signatures that are verified by this contract.
    function approveHash(bytes32 hashToApprove) external;

    /// @dev Allows to add a module to the whitelist.
    /// @param module Module to be whitelisted.
    function enableModule(address module) external;

    /// @dev Allows to execute a Safe transaction confirmed by required number of owners and then pays the account that submitted the transaction.
    /// @param to Destination address of Safe transaction.
    /// @param value Ether value of Safe transaction.
    /// @param data Data payload of Safe transaction.
    /// @param operation Operation type of Safe transaction.
    /// @param safeTxGas Gas that should be used for the Safe transaction.
    /// @param baseGas Gas costs that are independent of the transaction execution(e.g. base transaction fee, signature check, payment of the refund)
    /// @param gasPrice Gas price that should be used for the payment calculation.
    /// @param gasToken Token address (or 0 if ETH) that is used for the payment.
    /// @param refundReceiver Address of receiver of gas payment (or 0 if tx.origin).
    /// @param signatures Packed signature data ({bytes32 r}{bytes32 s}{uint8 v})
    function execTransaction(address to, uint256 value, bytes calldata data, Operation operation, uint256 safeTxGas,
        uint256 baseGas, uint256 gasPrice, address gasToken, address payable refundReceiver, bytes memory signatures)
        external payable returns (bool success);

    /// @dev Returns hash to be signed by owners.
    /// @param to Destination address.
    /// @param value Ether value.
    /// @param data Data payload.
    /// @param operation Operation type.
    /// @param safeTxGas Fas that should be used for the safe transaction.
    /// @param baseGas Gas costs for data used to trigger the safe transaction.
    /// @param gasPrice Maximum gas price that should be used for this transaction.
    /// @param gasToken Token address (or 0 if ETH) that is used for the payment.
    /// @param refundReceiver Address of receiver of gas payment (or 0 if tx.origin).
    /// @param _nonce Transaction nonce.
    /// @return Transaction hash.
    function getTransactionHash(address to, uint256 value, bytes calldata data, Operation operation, uint256 safeTxGas,
        uint256 baseGas, uint256 gasPrice, address gasToken, address refundReceiver, uint256 _nonce)
        external view returns (bytes32);

    /// @dev Allows a Module to execute a Safe transaction without any further confirmations.
    /// @param to Destination address of module transaction.
    /// @param value Ether value of module transaction.
    /// @param data Data payload of module transaction.
    /// @param operation Operation type of module transaction.
    function execTransactionFromModule(address to, uint256 value, bytes memory data,
        Operation operation) external returns (bool success);
}

interface IStakingManager {
    /// @dev Claims specified service rewards.
    /// @param serviceId Service Id.
    /// @return Staking reward.
    function claim(uint256 serviceId) external returns (uint256);
}

// ERC20 token interface
interface IToken {
    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);
}

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero value.
error ZeroValue();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as a manager.
error ManagerOnly(address sender, address manager);

/// @title ActivityModule - Smart contract for multisig activity tracking
contract ActivityModule {
    event ActivityIncreased(uint256 activityChange);

    uint256 public constant DEFAULT_ACTIVITY = 1;

    // OLAS token address
    address public immutable olas;
    // Rewards collector address
    address public immutable collector;

    // Activity tracker
    uint256 public activityNonce;
    // Service Id
    uint256 public serviceId;
    // Multisig address
    address public multisig;
    // Staking proxy address
    address public stakingProxy;
    // Staking manager address
    address public stakingManager;

    // Reentrancy lock
    uint256 internal _locked;

    /// @dev ActivityModule constructor.
    /// @param _olas OLAS address.
    /// @param _collector Collector address.
    constructor(address _olas, address _collector) {
        olas = _olas;
        collector = _collector;
    }

    function _increaseActivity(uint256 activityChange) internal {
        activityNonce += activityChange;

        emit ActivityIncreased(activityChange);
    }

    function initialize(address _multisig, address _stakingProxy, uint256 _serviceId) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        if (multisig != address(0)) {
            revert AlreadyInitialized();
        }

        // Check for zero address
        if (_multisig == address(0) || _stakingProxy == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero value
        if (_serviceId == 0) {
            revert ZeroValue();
        }

        multisig = _multisig;
        stakingProxy = _stakingProxy;
        stakingManager = msg.sender;
        serviceId = _serviceId;

        // Set up address(this) as multisig module
        // Get signature for approved hash case
        bytes32 r = bytes32(uint256(uint160(address(this))));
        bytes memory signature = abi.encodePacked(r, bytes32(0), uint8(1));

        // Encode enable module function call
        bytes memory data = abi.encodeCall(ISafe.enableModule, (address(this)));

        // Get multisig nonce
        uint256 nonce = ISafe(multisig).nonce();
        // Check for zero value, as only newly created multisig is considered valid
        if (nonce > 0) {
            revert AlreadyInitialized();
        }

        bytes32 txHash = ISafe(multisig).getTransactionHash(multisig, 0, data, ISafe.Operation.Call, 0, 0, 0,
            address(0),address(0), nonce);

        // Approve hash
        ISafe(multisig).approveHash(txHash);

        // Execute multisig transaction
        ISafe(multisig).execTransaction(multisig, 0, data, ISafe.Operation.Call, 0, 0, 0, address(0),
            payable(address(0)), signature);

        _locked = 1;
    }

    function increaseInitialActivity() external {
        if (msg.sender != stakingManager) {
            revert ManagerOnly(msg.sender, stakingManager);
        }

        _increaseActivity(DEFAULT_ACTIVITY);
    }

    function claim() external {
        // Get staking reward
        IStakingManager(stakingManager).claim(serviceId);

        // Increases activity for the next staking epoch
        _increaseActivity(DEFAULT_ACTIVITY);

        // Get multisig balance
        uint256 balance = IToken(olas).balanceOf(multisig);

        // Check for zero balance
        if (balance == 0) {
            revert ZeroValue();
        }

        // Encode olas transfer function call
        bytes memory data = abi.encodeCall(IToken.transfer, (collector, balance));

        // Send collected funds to collector
        ISafe(multisig).execTransactionFromModule(olas, 0, data, ISafe.Operation.Call);
    }
}
