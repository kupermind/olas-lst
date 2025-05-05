// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC6909} from "../../lib/solmate/src/tokens/ERC6909.sol";
import {Implementation, OwnerOnly, ZeroAddress} from "../Implementation.sol";
import {IToken} from "../interfaces/IToken.sol";

interface IDepository {
    /// @dev Calculates amounts and initiates cross-chain unstake request from specified models.
    /// @param unstakeAmount Total amount to unstake.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set staking proxies corresponding to each chain Id.
    /// @param bridgePayloads Bridge payloads corresponding to each chain Id.
    /// @param values Value amounts for each bridge interaction, if applicable.
    /// @return amounts Corresponding OLAS amounts for each staking proxy.
    function unstake(uint256 unstakeAmount, uint256[] memory chainIds, address[] memory stakingProxies,
        bytes[] memory bridgePayloads, uint256[] memory values) external payable returns (uint256[] memory amounts);
}

interface IST {
    /// @dev Redeems OLAS in exchange for stOLAS tokens.
    /// @param shares stOLAS amount.
    /// @param receiver Receiver account address.
    /// @param owner Token owner account address.
    /// @return assets OLAS amount.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    function stakedBalance() external returns(uint256);
}

/// @dev Only `depository` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param depository Required depository address.
error DepositoryOnly(address sender, address depository);

/// @dev Zero value.
error ZeroValue();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();


/// @title Treasury - Smart contract for treasury
contract Treasury is Implementation, ERC6909 {
    event WithdrawDelayUpdates(uint256 withdrawDelay);
    event WithdrawRequestInitiated(address indexed requester, uint256 indexed requestId, uint256 stAmount,
        uint256 olasAmount, uint256 withdrawTime);
    event WithdrawRequestExecuted(uint256 requestId, uint256 amount);

    address public immutable olas;
    address public immutable st;
    // Depository address
    address public immutable depository;

    // Total withdraw amount requested
    uint256 public withdrawAmountRequested;
    // Withdraw time delay
    uint256 public withdrawDelay;
    // Number of withdraw requests
    uint256 public numWithdrawRequests;

    // Reentrancy lock
    bool transient _locked;

    /// @dev Treasury constructor.
    /// @param _olas OLAS address.
    /// @param _st stOLAS address.
    /// @param _depository Depository address.
    constructor(address _olas, address _st, address _depository) {
        olas = _olas;
        st = _st;
        depository = _depository;
    }

    /// @dev Treasury initializer.
    function initialize(uint256 _withdrawDelay) external{
        // Check for already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        withdrawDelay = _withdrawDelay;
        owner = msg.sender;
    }

    /// @dev Changes withdraw delay value.
    /// @param newWithdrawDelay New withdraw delay value in seconds.
    function changeWithdrawDelay(uint256 newWithdrawDelay) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        withdrawDelay = newWithdrawDelay;
        emit WithdrawDelayUpdates(newWithdrawDelay);
    }

    /// @dev Requests withdraw of OLAS in exchange of provided stOLAS.
    /// @notice Vault reserves are used first. If there is a lack of OLAS reserves, the backup amount is requested
    ///         to be unstaked from other models.
    /// @param stAmount Provided stAmount to burn in favor of OLAS tokens.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of staking proxies corresponding to each chain Id.
    /// @param bridgePayloads Bridge payloads corresponding to each chain Id.
    /// @param values Value amounts for each bridge interaction, if applicable.
    /// @return requestId Withdraw request ERC-1155 token.
    /// @return olasAmount Calculated OLAS amount.
    function requestToWithdraw(
        uint256 stAmount,
        uint256[] memory chainIds,
        address[] memory stakingProxies,
        bytes[] memory bridgePayloads,
        uint256[] memory values
    ) external payable returns (uint256 requestId, uint256 olasAmount) {
        // Reentrancy guard
        if (_locked) {
            revert ReentrancyGuard();
        }
        _locked = true;

        // Check for zero value
        if (stAmount == 0) {
            revert ZeroValue();
        }

        // Get stOLAS
        IToken(st).transferFrom(msg.sender, address(this), stAmount);

        // Calculate withdraw time
        uint256 withdrawTime = block.timestamp + withdrawDelay;

        // Get withdraw request Id
        requestId = numWithdrawRequests;
        numWithdrawRequests = requestId + 1;

        // Push a pair of key defining variables into one key: withdrawTime | requestId
        // requestId occupies first 64 bits, withdrawTime occupies next bits as they both fit well in uint256
        requestId |= withdrawTime << 64;

        // Get current staked balance
        uint256 stakedBalanceBefore = IST(st).stakedBalance();

        // Redeem OLAS and burn stOLAS tokens
        olasAmount = IST(st).redeem(stAmount, address(this), address(this));

        // Mint request tokens
        _mint(msg.sender, requestId, olasAmount);

        // Update total withdraw amount requested
        withdrawAmountRequested += olasAmount;

        // Get updated staked balance
        uint256 stakedBalanceAfter = IST(st).stakedBalance();

        // If withdraw amount is bigger than the current one, need to unstake
        if (stakedBalanceBefore > stakedBalanceAfter) {
            uint256 withdrawDiff = stakedBalanceBefore - stakedBalanceAfter;

            IDepository(depository).unstake(withdrawDiff, chainIds, stakingProxies, bridgePayloads, values);
        }

        emit WithdrawRequestInitiated(msg.sender, requestId, stAmount, olasAmount, withdrawTime);
    }

    /// @dev Finalizes withdraw requests.
    /// @param requestIds Withdraw request Ids.
    /// @param amounts Token amounts corresponding to request Ids.
    function finalizeWithdrawRequests(uint256[] calldata requestIds, uint256[] calldata amounts) external {
        // Reentrancy guard
        if (_locked) {
            revert ReentrancyGuard();
        }
        _locked = true;

        uint256 totalAmount;
        // Traverse all withdraw requests
        for (uint256 i = 0; i < requestIds.length; ++i) {
            // Get amount for a specified withdraw request Id
            transferFrom(msg.sender, address(this), requestIds[i], amounts[i]);

            // Decode a pair of key defining variables from one key: withdrawTime | requestId
            // requestId occupies first 64 bits, withdrawTime occupies next bits as they both fit well in uint256
            uint256 requestId = requestIds[i] & type(uint64).max;

            uint256 numRequests = numWithdrawRequests;
            // This must never happen as otherwise token would not exist and none of it would be transferFrom-ed
            if (requestId >= numRequests) {
                revert Overflow(requestId, numRequests);
            }

            // It is safe to just move 64 bits as there is a single withdrawTime value after that
            uint256 withdrawTime = requestIds[i] >> 64;
            // Check for earliest possible withdraw time
            if (withdrawTime > block.timestamp) {
                revert();
            }

            // Burn withdraw tokens
            _burn(address(this), requestIds[i], amounts[i]);

            totalAmount += amounts[i];

            emit WithdrawRequestExecuted(requestIds[i], amounts[i]);
        }

        // Transfer total amount of OLAS
        // The transfer overflow check is not needed since balances are in sync
        // OLAS has been redeemed when withdraw request was posted
        IToken(olas).transfer(msg.sender, totalAmount);
    }

    /// @dev Gets withdraw request Id by request Id and withdraw time.
    /// @param requestId Withdraw request Id.
    /// @param withdrawTime Withdraw time.
    function getWithdrawRequestId(uint256 requestId, uint256 withdrawTime) external pure returns (uint256) {
        return requestId | (withdrawTime << 64);
    }

    /// @dev Gets withdraw request Id and time.
    /// @param withdrawRequestId Combined withdrawRequestId value.
    function getWithdrawIdAndTime(uint256 withdrawRequestId) external pure returns (uint256, uint256) {
        return ((withdrawRequestId & type(uint64).max), (withdrawRequestId >> 64));
    }
}