// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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

interface IVEOLAS {
    /// @dev Deposits `amount` tokens for `msg.sender` and locks for `unlockTime`.
    /// @param amount Amount to deposit.
    /// @param unlockTime Time when tokens unlock, rounded down to a whole week.
    function createLock(uint256 amount, uint256 unlockTime) external;

    /// @dev Withdraws all tokens for `msg.sender`. Only possible if the lock has expired.
    function withdraw() external;
}

/// @dev Zero address.
error ZeroAddress();

/// @dev Only `depository` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param depository Required sender address as a depository.
error DepositoryOnly(address sender, address depository);

/// @title Lock - Smart contract for veOLAS related lock and voting functions
contract Lock {
    // veOLAS address
    address public immutable ve;
    // OLAS address
    address public immutable olas;
    // Depository address
    address public immutable depository;

    /// @dev Lock constructor.
    /// @param _olas OLAS address.
    /// @param _ve veOLAS address.
    /// @param _depository Depository address.
    constructor(address _olas, address _ve, address _depository) {
        // Check for the zero address
        if (_olas == address(0) || _ve == address(0) || _depository == address(0)) {
            revert ZeroAddress();
        }

        ve = _ve;
        olas = _olas;
        depository = _depository;
    }

    function createLock(uint256 amount, uint256 unlockTime) external {
        if (msg.sender != depository) {
            revert DepositoryOnly(msg.sender, depository);
        }

        // Get OLAS from depository
        IToken(olas).transferFrom(msg.sender, address(this), amount);
        // Approve OLAS for veOLAS
        IToken(olas).approve(ve, amount);

        // Create lock
        IVEOLAS(ve).createLock(amount, unlockTime);
    }

    function unlock(address account, uint256 amount) external {
        // Withdraw veOLAS
        IVEOLAS(ve).withdraw();

        // TODO For testing purposes now
        // Transfer OLAS
        IToken(olas).transfer(depository, amount);

//        // Transfer OLAS
//        IToken(olas).transfer(account, amount);
    }
}
