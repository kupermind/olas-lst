// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC1155, ERC1155TokenReceiver} from "../../lib/autonolas-registries/lib/solmate/src/tokens/ERC1155.sol";
import {IToken} from "../interfaces/IToken.sol";

interface IDepository {
    /// @dev Calculates amounts and initiates cross-chain unstake request from specified models.
    /// @param unstakeAmount Total amount to unstake.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of sets of staking proxies corresponding to each chain Id.
    /// @param bridgePayloads Bridge payloads corresponding to each chain Id.
    /// @param values Value amounts for each bridge interaction, if applicable.
    /// @return amounts Corresponding OLAS amounts for each staking proxy.
    function processUnstake(uint256 unstakeAmount, uint256[] memory chainIds, address[][] memory stakingProxies,
        bytes[] memory bridgePayloads, uint256[] memory values) external payable returns (uint256[][] memory amounts);
}

interface ILock {
    /// @dev Increases lock amount and time.
    /// @param olasAmount OLAS amount.
    function increaseLock(uint256 olasAmount) external;
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Only `depository` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param depository Required depository address.
error DepositoryOnly(address sender, address depository);

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero value.
error ZeroValue();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @title Treasury - Smart contract for treasury
contract Treasury is ERC1155, ERC1155TokenReceiver {
    event ImplementationUpdated(address indexed implementation);
    event OwnerUpdated(address indexed owner);
    event TotalReservesUpdated(uint256 stakedBalance, uint256 totalReserves);
    event LockFactorUpdated(uint256 lockFactor);
    event Locked(address indexed account, uint256 olasAmount, uint256 lockAmount, uint256 vaultBalance);
    event WithdrawRequestInitiated(address indexed requester, uint256 indexed requestId, uint256 stAmount,
        uint256 olasAmount, uint256 withdrawTime);
    event WithdrawRequestExecuted(uint256 indexed requestId);

    // Code position in storage is keccak256("TREASURY_PROXY") = "0x9b3195704d7d8da1c9110d90b2bf37e7d1d93753debd922cc1f20df74288b870"
    bytes32 public constant TREASURY_PROXY = 0x9b3195704d7d8da1c9110d90b2bf37e7d1d93753debd922cc1f20df74288b870;
    // Max lock factor
    uint256 public constant MAX_LOCK_FACTOR = 10_000;

    address public immutable olas;
    address public immutable ve;
    address public immutable st;
    address public immutable lock;

    // Staked balance
    uint256 public stakedBalance;
    // Vault balance
    uint256 public vaultBalance;
    // Total OLAS reserves that include staked and vault balance
    uint256 public totalReserves;
    // Lock factor in 10_000 value
    uint256 public lockFactor;
    // Total withdraw amount requested
    uint256 public withdrawAmountRequested;
    // Withdraw time delay
    uint256 public withdrawDelay;
    // Number of withdraw requests
    uint256 public numWithdrawRequests;
    // Depository address
    address public depository;
    // Contract owner
    address public owner;

    // TODO change to initialize in prod
    constructor(address _olas, address _ve, address _st, address _lock, uint256 _lockFactor) {
        olas = _olas;
        ve = _ve;
        st = _st;
        lock = _lock;
        _lockFactor;

        owner = msg.sender;
    }

    /// @dev Treasury initializer.
    function initialize() external{
        // Check for already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        owner = msg.sender;
    }

    /// @dev Changes the contributors implementation contract address.
    /// @param newImplementation New implementation contract address.
    function changeImplementation(address newImplementation) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (newImplementation == address(0)) {
            revert ZeroAddress();
        }

        // Store the contributors implementation address
        assembly {
            sstore(TREASURY_PROXY, newImplementation)
        }

        emit ImplementationUpdated(newImplementation);
    }

    /// @dev Changes contract owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Check for ownership
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

    /// @dev Changes lock factor value.
    /// @param newLockFactor New lock factor value.
    function changeLockFactor(address newLockFactor) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (lockFactor == 0) {
            revert ZeroValue();
        }

        lockFactor = newLockFactor;
        emit LockFactorUpdated(newLockFactor);
    }

    function processAndMintStToken(address account, uint256 olasAmount) external returns (uint256 stAmount) {
        // Check for depository access
        if (msg.sender != depository) {
            revert DepositoryOnly(msg.sender, depository);
        }

        // Get staked OLAS balance
        uint256 curStakedBalance = stakedBalance;

        // Adjust staked balance
        curStakedBalance += olasAmount;
        stakedBalance = curStakedBalance;

        (, uint256 curTotalReserves) = _updateReserves(curStakedBalance);

        // Get stOLAS amount from the provided OLAS amount
        stAmount = (olasAmount * curTotalReserves) / curStakedBalance;

        // Mint stOLAS
        IToken(st).mint(account, stAmount);
    }

    function _increaseLock(uint256 olasAmount) internal returns (uint256 remainder) {
        // Get treasury veOLAS lock amount
        uint256 lockAmount = (olasAmount * lockFactor) / MAX_LOCK_FACTOR;
        remainder = olasAmount - lockAmount;

        // Approve OLAS for Lock
        IToken(olas).approve(ve, lockAmount);

        // Increase lock
        ILock(lock).increaseLock(lockAmount);

        emit Locked(msg.sender, olasAmount, lockAmount, remainder);
    }

    function _updateReserves(uint256 curStakedBalance)
        internal returns (uint256 curVaultBalance, uint256 curTotalReserves) {
        if (curStakedBalance == 0) {
            curStakedBalance = stakedBalance;
        }

        // Get current vault balance
        curVaultBalance = IToken(olas).balanceOf(address(this));
        // Get previous vault balance
        uint256 prevVaultBalance = vaultBalance;

        // Lock required amounts if balances changed positively
        if (curVaultBalance > prevVaultBalance) {
            uint256 lockRemainder = _increaseLock(curVaultBalance - prevVaultBalance);
            curVaultBalance = prevVaultBalance + lockRemainder;
        }
        vaultBalance = curVaultBalance;

        curTotalReserves = curStakedBalance + curVaultBalance;
        totalReserves = curTotalReserves;

        emit TotalReservesUpdated(curStakedBalance, curVaultBalance, curTotalReserves);
    }

    function updateReserves() external returns (uint256) {
        return _updateReserves(0);
    }

    /// @dev Deposits OLAS to treasury for vault and veOLAS lock.
    /// @notice Tokens are taken from `msg.sender`'s balance.
    /// @param olasAmount OLAS amount.
    function depositAndLock(uint256 olasAmount) external {
        IToken(olas).transferFrom(msg.sender, address(this), olasAmount);

        _updateReserves(0);
    }

    /// @dev Calculates amounts and initiates cross-chain unstake request from specified models.
    /// @param unstakeAmount Total amount to unstake.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of sets of staking proxies corresponding to each chain Id.
    /// @param bridgePayloads Bridge payloads corresponding to each chain Id.
    /// @param values Value amounts for each bridge interaction, if applicable.
    function _unstake(
        uint256 unstakeAmount,
        uint256[] memory chainIds,
        address[][] memory stakingProxies,
        bytes[] memory bridgePayloads,
        uint256[] memory values
    ) internal {
        uint256 curStakedBalance = stakedBalance;
        if (curStakedBalance < unstakeAmount) {
            revert Overflow(curStakedBalance, unstakeAmount);
        }

        // Update staked balance
        curStakedBalance -= unstakeAmount;
        stakedBalance = curStakedBalance;

        // Update reserves
        _updateReserves(curStakedBalance);

        // Calculate OLAS amounts and initiate unstake messages to L2-s
        IDepository(depository).processUnstake(unstakeAmount, chainIds, stakingProxies, bridgePayloads, values);
    }

    /// @dev Unstakes from specified staking models.
    /// @notice This allows to deduct reserves from their staked part and get them back as vault part.
    /// @param unstakeAmount Total amount to unstake.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of sets of staking proxies corresponding to each chain Id.
    /// @param bridgePayloads Bridge payloads corresponding to each chain Id.
    /// @param values Value amounts for each bridge interaction, if applicable.
    function unstake(
        uint256 unstakeAmount,
        uint256[] memory chainIds,
        address[][] memory stakingProxies,
        bytes[] memory bridgePayloads,
        uint256[] memory values
    ) external payable {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Update reserves
        _updateReserves(0);

        _unstake(unstakeAmount, chainIds, stakingProxies, bridgePayloads, values);
    }

    // TODO Move high level part to depository?
    /// @dev Requests withdraw of OLAS in exchange of provided stOLAS.
    /// @notice Vault reserves are used first. If there is a lack of OLAS reserves, the backup amount is requested
    ///         to be unstaked from other models.
    /// @param stAmount Provided stAmount to burn in favor of OLAS tokens.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of sets of staking proxies corresponding to each chain Id.
    /// @param bridgePayloads Bridge payloads corresponding to each chain Id.
    /// @param values Value amounts for each bridge interaction, if applicable.
    /// @return requestId Withdraw request ERC-1155 token.
    /// @return olasAmount Calculated OLAS amount.
    function requestToWithdraw(
        uint256 stAmount,
        uint256[] memory chainIds,
        address[][] memory stakingProxies,
        bytes[] memory bridgePayloads,
        uint256[] memory values
    ) external payable returns (uint256 requestId, uint256 olasAmount) {
        // Update reserves
        _updateReserves(0);

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

        // Calculate OLAS amount
        olasAmount = getOlasAmount(stAmount);
        // Mint request tokens
        _mint(msg.sender, requestId, olasAmount, "");

        uint256 curWithdrawAmountRequested = withdrawAmountRequested + olasAmount;
        withdrawAmountRequested = curWithdrawAmountRequested;
        uint256 curVaultBalance = vaultBalance;

        // If withdraw amount is bigger than the current one, need to unstake
        if (curWithdrawAmountRequested > curVaultBalance) {
            uint256 withdrawDiff = curWithdrawAmountRequested - curVaultBalance;

            _unstake(withdrawDiff, chainIds, stakingProxies, bridgePayloads, values);
        }

        // Burn stOLAS tokens
        IToken(st).burn(stAmount);

        emit WithdrawRequestInitiated(msg.sender, requestId, stAmount, olasAmount, withdrawTime);
    }

    /// @dev Finalizes withdraw requests.
    /// @param requestIds Withdraw request Ids.
    /// @param amounts Token amounts corresponding to request Ids.
    function finalizeWithdrawRequests(uint256[] memory requestIds, uint256[] memory amounts) external {
        // Update reserves
        _updateReserves(0);

        safeBatchTransferFrom(msg.sender, address(this), requestIds, amounts, "");

        uint256 totalAmount;
        // Traverse all withdraw requests
        for (uint256 i = 0; i < requestIds[i]; ++i) {
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

            totalAmount += amounts[i];

            emit WithdrawRequestExecuted(requestIds[i], amounts[i]);
        }

        // Burn withdraw tokens
        _batchBurn(address(this), requestIds, amounts);

        // Check underflows: this must never happen
        uint256 curVaultBalance = vaultBalance;
        if (totalAmount > curVaultBalance) {
            revert Overflow(totalAmount, curVaultBalance);
        }

        // Adjust vault balances directly to avoid calling updateReserves()
        curVaultBalance -= totalAmount;
        vaultBalance = curVaultBalance;
        // This is safa, as totalReserves is always >= vaultBalance
        totalReserves -= totalAmount;

        // Transfer total amount
        // The transfer overflow check is not needed since balances are in sync
        // This fails here
        IToken(olas).transfer(msg.sender, totalAmount);
    }

    /// @dev Gets stOLAS amount from provided OLAS amount.
    /// @param olasAmount OLAS amount.
    /// @return stOLAS amount.
    function getStAmount(uint256 olasAmount) external view returns (uint256) {
        // TODO MulDiv?
        return (olasAmount * stakedBalance) / totalReserves;
    }

    /// @dev Gets OLAS amount from provided stOLAS amount.
    /// @param stAmount stOLAS amount.
    /// @return OLAS amount.
    function getOlasAmount(uint256 stAmount) public view returns (uint256) {
        // TODO MulDiv? Rounding down to zero?
        return (stAmount * totalReserves) / stakedBalance;
    }

    function getWithdrawRequestId(uint256 requestId, uint256 withdrawTime) external pure returns (uint256) {
        return requestId | (withdrawTime << 64);
    }

    function getWithdrawIdAndTime(uint256 withdrawRequestId) external pure returns (uint256, uint256) {
        return ((withdrawRequestId & type(uint64).max), (withdrawRequestId >> 64));
    }
}