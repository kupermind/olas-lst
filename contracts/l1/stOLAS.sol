// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20, ERC4626, FixedPointMathLib} from  "../../lib/solmate/src/tokens/ERC4626.sol";
import {IToken} from "../l2/ActivityModule.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required owner address.
error OwnerOnly(address sender, address owner);

/// @dev Only `treasury` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param treasury Required sender address as a treasury.
error DepositoryOnly(address sender, address treasury);

/// @dev Only `depository` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param depository Required sender address as a depository.
error TreasuryOnly(address sender, address depository);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @title stOLAS - Smart contract for the stOLAS token.
contract stOLAS is ERC4626 {
    using FixedPointMathLib for uint256;

    event OwnerUpdated(address indexed owner);
    event ManagersUpdated(address indexed treasury, address indexed depository);
    event TotalReservesUpdated(uint256 stakedBalance, uint256 vaultBalance, uint256 reserveBalance, uint256 totalReserves);

    // Staked balance
    uint256 public stakedBalance;
    // Vault balance
    uint256 public vaultBalance;
    // Reserve balance
    uint256 public reserveBalance;
    // Total OLAS reserves that include staked and vault balance
    uint256 public totalReserves;
    // Top-up reserve balance in on-going deposit
    uint256 transient topUpBalance;

    // Owner address
    address public owner;
    // Treasury address
    address public treasury;
    // Depository address
    address public depository;

    constructor(ERC20 _olas) ERC4626(_olas, "Staked OLAS", "stOLAS") {
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Changes various managing contract addresses.
    /// @param newTreasury New treasury address.
    /// @param newDepository New depository address.
    function changeManagers(address newTreasury, address newDepository) external {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (newTreasury == address(0) || newDepository == address(0)) {
            revert ZeroAddress();
        }

        treasury = newTreasury;
        depository = newDepository;
        emit ManagersUpdated(newTreasury, newDepository);
    }

    /// @dev Deposits OLAS in exchange for stOLAS tokens.
    /// @param assets OLAS amount.
    /// @param receiver Receiver account address.
    /// @return shares stOLAS amount.
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        if (msg.sender != depository) {
            revert DepositoryOnly(msg.sender, depository);
        }

        // Check for zero balance
        if (assets == 0) {
            revert ZeroValue();
        }

        // Calculate and update all balances
        (uint256 curStakedBalance, uint256 curVaultBalance, uint256 curTotalReserves) = calculateBalances(assets);
        stakedBalance = curStakedBalance;
        vaultBalance = curVaultBalance;
        totalReserves = curTotalReserves;

        // Check for rounding error since we round down in convertToShares.
        require((shares = convertToShares(assets)) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        emit TotalReservesUpdated(curStakedBalance, curVaultBalance, reserveBalance, curTotalReserves);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function calculateBalances(uint256 assets) public view
        returns (uint256 curStakedBalance, uint256 curVaultBalance, uint256 curTotalReserves)
    {
        // topUpBalance is subtracted as it is passed as part of the assets value and already deposited
        // and accounted in vaultBalance via topUpReserveBalance() function call
        curStakedBalance = stakedBalance + assets - topUpBalance;

        // Get current vault balance
        curVaultBalance = asset.balanceOf(address(this));

        // Update total assets
        curTotalReserves = curStakedBalance + curVaultBalance;
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        (, , uint256 curTotalReserves) = calculateBalances(assets);

        uint256 supply = totalSupply;

        return supply == 0 ? assets : assets.mulDivDown(supply, curTotalReserves);
    }

    /// @dev Redeems OLAS in exchange for stOLAS tokens.
    /// @param shares stOLAS amount.
    /// @param receiver Receiver account address.
    /// @param tokenOwner Token owner account address.
    /// @return assets OLAS amount.
    function redeem(uint256 shares, address receiver, address tokenOwner) public override returns (uint256 assets) {
        if (msg.sender != treasury) {
            revert TreasuryOnly(msg.sender, treasury);
        }

        // TODO Optimize
        updateTotalAssets();

        // Check for rounding error since we round down in convertToAssets.
        require((assets = convertToAssets(shares)) != 0, "ZERO_ASSETS");

        _burn(tokenOwner, shares);

        // Update total assets
        // Get current staked and vault balance (including reserve balance)
        uint256 curStakedBalance = stakedBalance;
        uint256 curVaultBalance = asset.balanceOf(address(this));
        uint256 curReserveBalance = reserveBalance;
        uint256 transferAmount;

        // TODO optimize?
        if (curVaultBalance > assets) {
            transferAmount = assets;

            // Reserve balance update
            if (assets > curReserveBalance) {
                curReserveBalance = 0;
                curVaultBalance -= (assets - curReserveBalance);
            } else {
                curReserveBalance -= assets;
            }
        } else {
            transferAmount = curVaultBalance;
            uint256 diff = assets - curVaultBalance;
            curVaultBalance = 0;

            // Check for overflow, must never happen
            if (diff > curStakedBalance) {
                revert Overflow(diff, curStakedBalance);
            }

            curStakedBalance -= diff;
            stakedBalance = curStakedBalance;
            curReserveBalance = 0;
        }

        reserveBalance = curReserveBalance;
        uint256 curTotalReserves = curStakedBalance + curVaultBalance;
        totalReserves = curTotalReserves;
        vaultBalance = curVaultBalance;

        asset.transfer(receiver, transferAmount);

        emit TotalReservesUpdated(curStakedBalance, curVaultBalance, curReserveBalance, curTotalReserves);
        emit Withdraw(msg.sender, receiver, tokenOwner, assets, shares);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        //updateTotalAssets
        // TODO
        uint256 curTotalReserves = totalAssets();

        uint256 supply = totalSupply;

        return supply == 0 ? shares : shares.mulDivDown(curTotalReserves, supply);
    }

    /// @dev Overrides mint function that is never used.
    function mint(uint256, address) public pure override returns (uint256) {
        return 0;
    }

    /// @dev Overrides withdraw function that is never used.
    function withdraw(uint256, address, address) public pure override returns (uint256) {
        return 0;
    }

    function topUpReserveBalance(uint256 amount) external {
        if (msg.sender != depository) {
            revert();
        }

        asset.transferFrom(msg.sender, address(this), amount);
        topUpBalance = amount;
        reserveBalance += amount;

        // TODO event or Transfer event is enough?
    }

    function fundDepository() external {
        if (msg.sender != depository) {
            revert();
        }

        uint256 curReserveBalance = reserveBalance;
        if (curReserveBalance > 0) {
            reserveBalance = 0;
            totalReserves -= curReserveBalance;
            asset.transfer(msg.sender, curReserveBalance);
        }

        // TODO event or Transfer event is enough?
    }

    // TODO Optimize
    function updateTotalAssets() public {
        uint256 curStakedBalance = stakedBalance;

        // Get current vault balance
        uint256 curVaultBalance = asset.balanceOf(address(this));
        vaultBalance = curVaultBalance;

        uint256 curTotalReserves = curStakedBalance + curVaultBalance;
        totalReserves = curTotalReserves;

        emit TotalReservesUpdated(curStakedBalance, curVaultBalance, reserveBalance, curTotalReserves);
    }
    
    function totalAssets() public view override returns (uint256) {
        return totalReserves;
    }
}