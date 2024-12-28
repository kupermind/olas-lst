// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626} from  "../../lib/solmate/src/tokens/ERC4626.sol";

/// @dev Only `minter` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param minter Required sender address as a minter.
error MinterOnly(address sender, address minter);

/// @dev Provided zero address.
error ZeroAddress();

/// @title stOLAS - Smart contract for the stOLAS token.
contract stOLAS is ERC4626 {
    event MinterUpdated(address indexed minter);

    // Minter address
    address public minter;

    constructor(address _olas) ERC4626(_olas, "Staked OLAS", "stOLAS") {
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

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        if (msg.sender != minter) {
            revert MinterOnly(msg.sender, minter);
        }

        shares = super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        if (msg.sender != minter) {
            revert MinterOnly(msg.sender, minter);
        }

        assets = super.mint(assets, receiver);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        if (msg.sender != minter) {
            revert MinterOnly(msg.sender, minter);
        }

        shares = super.withdraw(assets, receiver, owner);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != minter) {
            revert MinterOnly(msg.sender, minter);
        }
        
        assets = super.redeem(assets, receiver, owner);
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

    /// @dev Burns stOLAS tokens.
    /// @param amount stOLAS token amount to burn.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}