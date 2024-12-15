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
    event LockFactorUpdated(uint256 lockFactor);
    event Vault(address indexed account, uint256 olasAmount, uint256 lockAmount, uint256 vaultBalance);

    // Code position in storage is keccak256("TREASURY_PROXY") = "0x9b3195704d7d8da1c9110d90b2bf37e7d1d93753debd922cc1f20df74288b870"
    bytes32 public constant TREASURY_PROXY = 0x9b3195704d7d8da1c9110d90b2bf37e7d1d93753debd922cc1f20df74288b870;
    // Maximum veOLAS lock time (4 years)
    uint256 public constant MAX_LOCK_TIME = 4 * 365 * 1 days;


    address public immutable olas;
    address public immutable ve;
    address public immutable st;

    // Vault balance
    uint256 public vaultBalance;
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

    function calculateAndMint(uint256 olasAmount) external {
        // Get stOLAS amount from the provided OLAS amount
        stAmount = getStAmount(olasAmount);

        // Get OLAS from sender
        IToken(olas).transferFrom(msg.sender, address(this), olasAmount);

        // Mint stOLAS
        ITreasury(st).mint(msg.sender, stAmount);
    }

    /// @dev Deposits OLAS to treasury for vault and veOLAS lock.
    /// @notice Tokens are taken from `msg.sender`'s balance.
    /// @param olasAmount OLAS amount.
    function depositAndLock(uint256 olasAmount) external {
        IToken(olas).transferFrom(msg.sender, address(this), olasAmount);

        // Get treasury veOLAS lock amount
        uint256 lockAmount = (olasAmount * lockFactor) / 10_000;
        uint256 vaultAmount = olasAmount - lockAmount;

        vaultAmount += vaultBalance;
        vaultBalance = vaultAmount;

        // Approve OLAS for veOLAS
        IToken(olas).approve(ve, lockAmount);

        LockedBalance memory lockedBalance = IVEOLAS(ve).mapLockedBalances(address(this));
        // Lock if never was locked or unlocked
        if (lockedBalance.amount == 0) {
            IVEOLAS(ve).createLock(lockAmount, MAX_LOCK_TIME);
        } else {
            // Increase amount and unlock time to a maximum
            IVEOLAS(ve).increaseAmount(lockAmount);
            IVEOLAS(ve).increaseUnlockTime(MAX_LOCK_TIME);
        }

        emit Vault(msg.sender, olasAmount, lockAmount, vaultAmount);
    }

    function requestToWithdraw(uint256 stAmount) external returns (uint256 requestId, uint256 olasAmount) {
        IToken(st).transferFrom(msg.sender, address(this), stAmount);

        // TODO cyclic map requests
    }

    function cancelWithdrawRequest(uint256 requestId) external {
        // TODO kick request out of the map
    }

    function getStAmount(uint256 olasAmount) public view returns (uint256 stAmount) {
        stAmount = olasAmount;
    }

    // TODO: Fix math
    function getOLASAmount(uint256 stAmount) public view returns (uint256 olasAmount) {
        olasAmount = (stAmount * 1.00000001 ether) / 1 ether;
    }
}