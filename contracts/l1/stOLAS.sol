// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20, ERC4626} from  "../../lib/solmate/src/tokens/ERC4626.sol";

/// @dev Only `minter` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param minter Required sender address as a minter.
error MinterOnly(address sender, address minter);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @title stOLAS - Smart contract for the stOLAS token.
contract stOLAS is ERC4626 {
    event MinterUpdated(address indexed minter);
    event TotalReservesUpdated(uint256 stakedBalance, uint256 vaultBalance, uint256 totalReserves);

    // Staked balance
    uint256 public stakedBalance;
    // Vault balance
    uint256 public vaultBalance;
    // Total OLAS reserves that include staked and vault balance
    uint256 public totalReserves;

    // Minter address
    address public minter;

    constructor(ERC20 _olas) ERC4626(_olas, "Staked OLAS", "stOLAS") {
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

    /// @dev Deposits OLAS in exchange for stOLAS tokens.
    /// @param assets OLAS amount.
    /// @param receiver Receiver account address.
    /// @return shares stOLAS amount.
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        if (msg.sender != minter) {
            revert MinterOnly(msg.sender, minter);
        }

        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @dev Redeems OLAS in exchange for stOLAS tokens.
    /// @param shares stOLAS amount.
    /// @param receiver Receiver account address.
    /// @param owner Token owner account address.
    /// @return assets OLAS amount.
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        if (msg.sender != minter) {
            revert MinterOnly(msg.sender, minter);
        }

        // TODO Is this check needed?
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        _burn(owner, shares);

        // Get current staked and vault balance
        uint256 curStakedBalance = stakedBalance;
        uint256 curVaultBalance = asset.balanceOf(address(this));
        uint256 transferAmount;

        if (curVaultBalance > assets) {
            transferAmount = assets;
            // TODO: use when updating in-place
//            curVaultBalance -= assets;
        } else {
            transferAmount = curVaultBalance;
            // TODO: use when updating in-place
//            uint256 diff = assets - curVaultBalance;
//            curVaultBalance = 0;
//            curStakedBalance -= diff;
//            stakedBalance = curStakedBalance;
        }

        // TODO: use when updating in-place
//        uint256 curTotalReserves = curStakedBalance + curVaultBalance;
//        totalReserves = curTotalReserves;
//        vaultBalance = curVaultBalance;

        asset.transfer(receiver, transferAmount);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /// @dev Overrides mint function that is never used.
    function mint(uint256, address) public override returns (uint256) {
        return 0;
    }

    /// @dev Overrides withdraw function that is never used.
    function withdraw(uint256, address, address) public override returns (uint256) {
        return 0;
    }

    // TODO Optimize
    function updateTotalAssetsVault() external {
        // TODO Vault inflation attack
        uint256 curStakedBalance = stakedBalance;

        // TODO Change with function balanceOf()
        // Get current vault balance
        uint256 curVaultBalance = asset.balanceOf(address(this));
        vaultBalance = curVaultBalance;

        uint256 curTotalReserves = curStakedBalance + curVaultBalance;
        totalReserves = curTotalReserves;

        emit TotalReservesUpdated(curStakedBalance, curVaultBalance, curTotalReserves);
    }

    // TODO Perform in deposit / redeem
    function updateTotalAssets(int256 assets) external {
        if (msg.sender != minter) {
            revert MinterOnly(msg.sender, minter);
        }

        uint256 curStakedBalance = stakedBalance;
        if (assets < 0 && (int256(curStakedBalance) < -assets)) {
            revert Overflow(uint256(-assets), curStakedBalance);
        }

        if (assets != 0) {
            curStakedBalance = uint256(int256(curStakedBalance) + assets);
            stakedBalance = curStakedBalance;
        }

        // TODO Vault inflation attack
        // Get current vault balance
        uint256 curVaultBalance = asset.balanceOf(address(this));
        vaultBalance = curVaultBalance;

        uint256 curTotalReserves = curStakedBalance + curVaultBalance;
        totalReserves = curTotalReserves;

        emit TotalReservesUpdated(curStakedBalance, curVaultBalance, curTotalReserves);
    }
    
    function totalAssets() public view override returns (uint256) {
        return totalReserves;
    }
}