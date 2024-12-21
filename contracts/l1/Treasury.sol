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
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as an owner.
error ManagerOnly(address sender, address manager);

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero value.
error ZeroValue();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @title Treasury - Smart contract for the treasury.
contract Treasury {
    event ImplementationUpdated(address indexed implementation);
    event OwnerUpdated(address indexed owner);
    event TotalReservesUpdated(uint256 stakedBalance, uint256 totalReserves);
    event LockFactorUpdated(uint256 lockFactor);
    event Vault(address indexed account, uint256 olasAmount, uint256 lockAmount, uint256 vaultBalance);

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
    address public depository;
    address public owner;

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
        uint256 localStakedBalance = stakedBalance;

        // Adjust staked balance
        localStakedBalance += olasAmount;
        stakedBalance = localStakedBalance;

        uint256 localTotalReserves = _updateReserves(localStakedBalance);

        // Get stOLAS amount from the provided OLAS amount
        stAmount = (olasAmount * localTotalReserves) / localStakedBalance;

        // Mint stOLAS
        IToken(st).mint(account, stAmount);
    }

    function _updateReserves(uint256 localStakedBalance) internal returns (uint256) {
        if (localStakedBalance == 0) {
            localStakedBalance = stakedBalance;
        }

        // Get current vault balance
        uint256 curVaultBalance = IToken(olas).balanceOf(address(this));
        // Get previous vault balance
        uint256 prevVaultBalance = vaultBalance;

        // Lock required amounts if balances changed positively
        if (curVaultBalance > prevVaultBalance) {
            uint256 lockRemainder = _lock(curVaultBalance - prevVaultBalance);
            curVaultBalance = prevVaultBalance + lockRemainder;
        }
        vaultBalance = curVaultBalance;

        uint256 localTotalReserves = localStakedBalance + curVaultBalance;
        totalReserves = localTotalReserves;

        emit TotalReservesUpdated(localStakedBalance, localTotalReserves);

        return localTotalReserves;
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

        emit Vault(msg.sender, olasAmount, lockAmount, remainder);
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
        IToken(st).transferFrom(msg.sender, address(this), stAmount);

        // TODO cyclic map requests
    }

    function cancelWithdrawRequest(uint256 requestId) external {
        // TODO kick request out of the map
    }

    function getStAmount(uint256 olasAmount) external view returns (uint256 stAmount) {
        // TODO MulDiv?
        stAmount = (olasAmount * totalReserves) / stakedBalance;
    }
    
    function getOLASAmount(uint256 stAmount) public view returns (uint256 olasAmount) {
        // TODO MulDiv? Rounding down to zero?
        olasAmount = (stAmount * stakedBalance) / totalReserves;
    }
}