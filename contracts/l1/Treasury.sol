// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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

    function mapLockedBalances(address account) external returns (LockedBalance memory);
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

    /// @dev Mints stOLAS tokens.
    /// @param account Account address.
    /// @param amount stOLAS token amount.
    function mint(address account, uint256 amount) external;
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

struct WithdrawRequest {
    address requester;
    uint96 stAmount;
    uint96 olasAmount;
    uint32 withdrawTime;
}

/// @title Treasury - Smart contract for the treasury.
contract Treasury {
    event ImplementationUpdated(address indexed implementation);
    event OwnerUpdated(address indexed owner);
    event TotalReservesUpdated(uint256 stakedBalance, uint256 totalReserves);
    event LockFactorUpdated(uint256 lockFactor);
    event Locked(address indexed account, uint256 olasAmount, uint256 lockAmount, uint256 vaultBalance);
    event WithdrawRequestInitiated(address indexed requester, uint256 indexed requestId, uint256 stAmount,
        uint256 olasAmount, uint256 withdrawTime);
    event WithdrawRequestCanceled(uint256 indexed requestId);
    event WithdrawRequestExecuted(uint256 indexed requestId);

    // Code position in storage is keccak256("TREASURY_PROXY") = "0x9b3195704d7d8da1c9110d90b2bf37e7d1d93753debd922cc1f20df74288b870"
    bytes32 public constant TREASURY_PROXY = 0x9b3195704d7d8da1c9110d90b2bf37e7d1d93753debd922cc1f20df74288b870;
    // Max lock factor
    uint256 public constant MAX_LOCK_FACTOR = 10_000;
    // Maximum veOLAS lock time (4 years)
    uint256 public constant MAX_LOCK_TIME = 4 * 365 * 1 days;


    address public immutable olas;
    address public immutable ve;
    address public immutable st;

    // Staked balance
    uint256 public stakedBalance;
    // Vault balance
    uint256 public vaultBalance;
    // Total OLAS reserves that include staked and vault balance
    uint256 public totalReserves;
    // Lock factor in 10_000 value
    uint256 public lockFactor;
    // Withdraw time delay
    uint256 public withdrawDelay;
    // Number of withdraw requests
    uint256 public numWithdrawRequests;
    // Depository address
    address public depository;
    // Contract owner
    address public owner;

    mapping(uint256 => WithdrawRequest) public mapWithdrawRequests;

    // TODO change to initialize in prod
    constructor(address _olas, address _ve, address _st, uint256 _lockFactor) {
        olas = _olas;
        ve = _ve;
        st = _st;
        _lockFactor;

        owner = msg.sender;
    }

    /// @dev Contributors initializer.
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

    function firstLock(uint256 olasAmount) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        IToken(olas).transferFrom(msg.sender, address(this), olasAmount);
        IVEOLAS(ve).createLock(olasAmount, MAX_LOCK_TIME);
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
            uint256 lockRemainder = _lock(curVaultBalance - prevVaultBalance);
            curVaultBalance = prevVaultBalance + lockRemainder;
        }
        vaultBalance = curVaultBalance;

        curTotalReserves = curStakedBalance + curVaultBalance;
        totalReserves = curTotalReserves;

        emit TotalReservesUpdated(curStakedBalance, curVaultBalance, curTotalReserves);
    }

    function updateReserves() public returns (uint256) {
        return _updateReserves(0);
    }

    function _lock(uint256 olasAmount) internal returns (uint256 remainder) {
        // Get treasury veOLAS lock amount
        uint256 lockAmount = (olasAmount * lockFactor) / MAX_LOCK_FACTOR;
        remainder = olasAmount - lockAmount;

        // Approve OLAS for veOLAS
        IToken(olas).approve(ve, lockAmount);

        // Increase amount and unlock time to a maximum
        IVEOLAS(ve).increaseAmount(lockAmount);
        IVEOLAS(ve).increaseUnlockTime(MAX_LOCK_TIME);

        emit Locked(msg.sender, olasAmount, lockAmount, remainder);
    }

    /// @dev Deposits OLAS to treasury for vault and veOLAS lock.
    /// @notice Tokens are taken from `msg.sender`'s balance.
    /// @param olasAmount OLAS amount.
    function depositAndLock(uint256 olasAmount) external {
        IToken(olas).transferFrom(msg.sender, address(this), olasAmount);

        _updateReserves(0);
    }

    /// TBD
    function unlock() external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // TODO Never withdraw the full amount, i.e. neve close the treasury lock
        LockedBalance memory lockedBalance = IVEOLAS(ve).mapLockedBalances(address(this));
    }

    function requestToWithdraw(uint256 stAmount) external returns (uint256 requestId, uint256 olasAmount) {
        // Update reserves
        _updateReserves(0);

        // Get stOLAS
        IToken(st).transferFrom(msg.sender, address(this), stAmount);

        requestId = numWithdrawRequests;
        numWithdrawRequests = requestId + 1;

        WithdrawRequest storage withdrawRequest = mapWithdrawRequests[requestId];
        withdrawRequest.requester = msg.sender;
        withdrawRequest.stAmount = stAmount;

        olasAmount = getOlasAmount(stAmount);
        // TODO any checks or now overflow is possible?
        withdrawRequest.olasAmount = olasAmount;

        uint256 withdrawTime = block.timestamp + withdrawDelay;
        withdrawRequest.withdrawTime = withdrawTime;

        emit WithdrawRequestInitiated(msg.sender, requestId, stAmount, olasAmount, withdrawTime);
    }

    function cancelWithdrawRequests(uint256[] memory requestIds) external {
        // Traverse all withdraw requests
        for (uint256 i = 0; i < requestIds[i]; ++i) {
            // Get withdraw request
            WithdrawRequest storage withdrawRequest = mapWithdrawRequests[requestIds[i]];
            // Check for request owner
            if (msg.sender != withdrawRequest.requester) {
                revert OwnerOnly(msg.sender, withdrawRequest.requester);
            }

            delete mapWithdrawRequests[requestIds[i]];

            emit WithdrawRequestCanceled(requestIds[i]);
        }
    }

    function finalizeWithdrawRequests(uint256[] memory requestIds) external {
        // Update reserves
        _updateReserves(0);

        uint256 totalAmount;
        // Traverse all withdraw requests
        for (uint256 i = 0; i < requestIds[i]; ++i) {
            // Get withdraw request
            WithdrawRequest storage withdrawRequest = mapWithdrawRequests[requestIds[i]];

            // Check for earliest possible withdraw time
            if (withdrawRequest.withdrawTime > block.timestamp) {
                revert();
            }

            uint256 amount = withdrawRequest.olasAmount;
            totalAmount += amount;

            emit WithdrawRequestExecuted(requestIds[i]);
        }

        // TODO any checks or now overflow is possible?

        // Transfer total amount
        // The transfer overflow check is not needed since balances are in sync
        IToken(olas).transfer(msg.sender, totalAmount);

        // Adjust vault balances directly to avoid calling updateReserves()
        vaultBalance -= totalAmount;
        totalReserves -= totalAmount;
    }

    function getStAmount(uint256 olasAmount) external view returns (uint256 stAmount) {
        // TODO MulDiv?
        stAmount = (olasAmount * totalReserves) / stakedBalance;
    }

    function getOlasAmount(uint256 stAmount) public view returns (uint256 olasAmount) {
        // TODO MulDiv? Rounding down to zero?
        olasAmount = (stAmount * stakedBalance) / totalReserves;
    }
}