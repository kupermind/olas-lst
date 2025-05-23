// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20, ERC4626, FixedPointMathLib} from  "../../lib/solmate/src/tokens/ERC4626.sol";
import {IToken} from "../l2/ActivityModule.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required owner address.
error OwnerOnly(address sender, address owner);

/// @dev Only `treasury` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param treasury Required sender address as a treasury.
error TreasuryOnly(address sender, address treasury);

/// @dev Only `depository` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param depository Required sender address as a depository.
error DepositoryOnly(address sender, address depository);

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
    event ReserveBalanceTopUpped(uint256 amount);
    event DepositoryFunded(uint256 amount);

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

    /// @dev stOLAS constructor.
    /// @param _olas OLAS token address.
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

        // Calculate and update all balances and total reserves
        (uint256 curStakedBalance, uint256 curVaultBalance, uint256 curTotalReserves) = calculateDepositBalances(assets);
        stakedBalance = curStakedBalance;
        vaultBalance = curVaultBalance;
        totalReserves = curTotalReserves;

        // Calculate shares
        shares = totalSupply;
        shares = shares == 0 ? assets : assets.mulDivDown(shares, curTotalReserves);

        // Check for rounding error since we round down in mulDivDown
        if (shares == 0) {
            revert ZeroValue();
        }

        _mint(receiver, shares);

        emit TotalReservesUpdated(curStakedBalance, curVaultBalance, reserveBalance, curTotalReserves);
        emit Deposit(msg.sender, receiver, assets, shares);
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

        (uint256 curStakedBalance, uint256 curVaultBalance, uint256 curReserveBalance, uint256 curTotalReserves) =
            calculateCurrentBalances();

        // Calculate assets
        assets = totalSupply;
        assets = assets == 0 ? shares : shares.mulDivDown(curTotalReserves, assets);

        // Check for rounding error since we round down in mulDivDown
        if (assets == 0) {
            revert ZeroValue();
        }

        _burn(tokenOwner, shares);

        // Update total assets
        uint256 transferAmount;

        // Shuffle balances depending on how many tokens are requested for redeem
        if (curVaultBalance >= assets) {
            // If vault has enough balance, use it first
            transferAmount = assets;
            curVaultBalance -= assets;
            curReserveBalance = curReserveBalance > assets ? curReserveBalance - assets : 0;
        } else {
            // If vault doesn't have enough, use all vault balance and take rest from staked
            transferAmount = curVaultBalance;
            uint256 remainingAmount = assets - curVaultBalance;
            
            // Check for overflow, must never happen
            if (remainingAmount > curStakedBalance) {
                revert Overflow(remainingAmount, curStakedBalance);
            }
            
            curStakedBalance -= remainingAmount;
            stakedBalance = curStakedBalance;
            curVaultBalance = 0;
            curReserveBalance = 0;
        }

        reserveBalance = curReserveBalance;
        vaultBalance = curVaultBalance;
        curTotalReserves = curStakedBalance + curVaultBalance;
        totalReserves = curTotalReserves;

        asset.transfer(receiver, transferAmount);

        emit TotalReservesUpdated(curStakedBalance, curVaultBalance, curReserveBalance, curTotalReserves);
        emit Withdraw(msg.sender, receiver, tokenOwner, assets, shares);
    }

    /// @dev Overrides mint function that is never used.
    function mint(uint256, address) public pure override returns (uint256) {
        return 0;
    }

    /// @dev Overrides withdraw function that is never used.
    function withdraw(uint256, address, address) public pure override returns (uint256) {
        return 0;
    }

    /// @dev Updates total assets.
    function updateTotalAssets() external returns (uint256) {
        (uint256 curStakedBalance, uint256 curVaultBalance, uint256 curReserveBalance, uint256 curTotalReserves) =
            calculateCurrentBalances();

        vaultBalance = curVaultBalance;
        totalReserves = curTotalReserves;

        emit TotalReservesUpdated(curStakedBalance, curVaultBalance, curReserveBalance, curTotalReserves);

        return curTotalReserves;
    }

    /// @dev Top-ups reserve balance via Depository.
    /// @param amount OLAS amount.
    function topUpReserveBalance(uint256 amount) external {
        if (msg.sender != depository) {
            revert DepositoryOnly(msg.sender, depository);
        }

        asset.transferFrom(msg.sender, address(this), amount);
        topUpBalance = amount;
        reserveBalance += amount;

        emit ReserveBalanceTopUpped(amount);
    }

    /// @dev Funds Depository with reserve balances.
    function fundDepository() external {
        if (msg.sender != depository) {
            revert DepositoryOnly(msg.sender, depository);
        }

        uint256 curReserveBalance = reserveBalance;
        if (curReserveBalance > 0) {
            reserveBalance = 0;
            totalReserves -= curReserveBalance;
            asset.transfer(msg.sender, curReserveBalance);
        }

        emit DepositoryFunded(curReserveBalance);
    }

    /// @dev Calculates balances for deposit.
    /// @param assets Deposited assets amount.
    /// @return curStakedBalance Current staked balance.
    /// @return curVaultBalance Current vault balance.
    /// @return curTotalReserves Current total reserves.
    function calculateDepositBalances(uint256 assets) public view
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

    /// @dev Previews deposit assets to shares amount.
    /// @param assets Deposited assets amount.
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        (, , uint256 curTotalReserves) = calculateDepositBalances(assets);

        uint256 shares = totalSupply;
        return shares == 0 ? assets : assets.mulDivDown(shares, curTotalReserves);
    }

    /// @dev Calculates current balances.
    /// @return curStakedBalance Current staked balance.
    /// @return curVaultBalance Current vault balance.
    /// @return curReserveBalance Current reserve balance.
    /// @return curTotalReserves Current total reserves.
    function calculateCurrentBalances() public view
        returns (uint256 curStakedBalance, uint256 curVaultBalance, uint256 curReserveBalance, uint256 curTotalReserves)
    {
        // Get staked and reserve balances
        curStakedBalance = stakedBalance;
        curReserveBalance = reserveBalance;

        // Current vault balance
        curVaultBalance = asset.balanceOf(address(this));

        // Total reserves
        curTotalReserves = curStakedBalance + curVaultBalance;
    }

    /// @dev Previews redeem shares to assets amount.
    /// @param shares Redeemed shares amount.
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        (, , , uint256 curTotalReserves) = calculateCurrentBalances();

        uint256 assets = totalSupply;
        return assets == 0 ? shares : shares.mulDivDown(curTotalReserves, assets);
    }

    /// @dev Gets total assets amount.
    function totalAssets() public view override returns (uint256) {
        return totalReserves;
    }

    /// @dev Gets total stake assets amount: currently staked and reserved for staking.
    function totalStakeAssets() external view virtual returns (uint256) {
        return stakedBalance + reserveBalance;
    }
}