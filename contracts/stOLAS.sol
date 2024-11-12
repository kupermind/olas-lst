// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from  "../lib/autonolas-registries/lib/solmate/src/tokens/ERC20.sol";

/// @dev Only `minter` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param minter Required sender address as a minter.
error MinterOnly(address sender, address minter);

/// @dev Provided zero address.
error ZeroAddress();

/// @title stOLAS - Smart contract for the stOLAS token.
contract stOLAS is ERC20 {
    event MinterUpdated(address indexed minter);

    // Minter address
    address public minter;

    constructor() ERC20("Staked OLAS", "stOLAS", 18) {
        minter = msg.sender;
    }

    /// @dev Changes the minter address.
    /// @param newMinter Address of a new minter.
    function changeMinter(address newMinter) external {
        if (msg.sender != minter) {
            revert MinterOnly(msg.sender, minter);
        }

        if (newMinter == address(0)) {
            revert ZeroAddress();
        }

        minter = newMinter;
        emit MinterUpdated(newMinter);
    }

    /// @dev Mints stOLAS tokens.
    /// @param account Account address.
    /// @param amount stOLAS token amount.
    function mint(address account, uint256 amount) external {
        // Access control
        if (msg.sender != minter) {
            revert MinterOnly(msg.sender, minter);
        }

        _mint(account, amount);
    }
}