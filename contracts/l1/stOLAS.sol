// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "hardhat/console.sol";
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

/// @dev Only `distributor` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param distributor Required sender address as a distributor.
error DistributorOnly(address sender, address distributor);

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
    event ManagersUpdated(address indexed treasury, address indexed depository, address indexed dstributor);
    event TotalReservesUpdated(uint256 stakedBalance, uint256 vaultBalance, uint256 reserveBalance, uint256 totalReserves);
    event ReserveBalanceTopUpped(uint256 amount);
    event VaultBalanceTopUpped(uint256 amount);
    event DepositoryFunded(uint256 amount);

    // Staked balance: funds allocated for staking contracts on different chains
    uint256 public stakedBalance;
    // Vault balance: Distributor and other possible deposits
    uint256 public vaultBalance;
    // Reserve balance: Depository incoming funds that are still not utilized
    uint256 public reserveBalance;
    // Total OLAS reserves that include staked, vault and reserve balance
    uint256 public totalReserves;
    // Top-up reserve balance in on-going deposit
    uint256 transient topUpBalance;

    // Owner address
    address public owner;
    // Treasury address
    address public treasury;
    // Depository address
    address public depository;
    // Distributor address
    address public distributor;

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
    /// @param newDistributor New distributor address.
    function changeManagers(address newTreasury, address newDepository, address newDistributor) external {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (newTreasury == address(0) || newDepository == address(0) || newDistributor == address(0)) {
            revert ZeroAddress();
        }

        treasury = newTreasury;
        depository = newDepository;
        distributor = newDistributor;
        emit ManagersUpdated(newTreasury, newDepository, newDistributor);
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

        // Get all balances and update total reserves
        (uint256 curStakedBalance, uint256 curVaultBalance, uint256 curReserveBalance, uint256 curTotalReserves) =
            calculateDepositBalances(assets);

        // Record updated balances
        stakedBalance = curStakedBalance;
        totalReserves = curTotalReserves;

        // Calculate shares
        shares = totalSupply;
        shares = shares == 0 ? assets : assets.mulDivDown(shares, curTotalReserves);

        // Check for rounding error since we round down in mulDivDown
        if (shares == 0) {
            revert ZeroValue();
        }

        _mint(receiver, shares);

        emit TotalReservesUpdated(curStakedBalance, curVaultBalance, curReserveBalance, curTotalReserves);
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

        uint256 vaultAndReserveBalance = curVaultBalance + curReserveBalance;
        // Shuffle balances depending on how many tokens are requested for redeem
        if (vaultAndReserveBalance >= assets) {
            // Vault and reserves have enough assets to cover requested amount
            transferAmount = assets;

            // Check if reserve balance can fully cover requested amount
            if (curReserveBalance >= assets) {
                curReserveBalance -= assets;
            } else {
                // Otherwise fully utilize reserve balance and use the rest from vault balance
                curVaultBalance = vaultAndReserveBalance - assets;
                curReserveBalance = 0;
            }
        } else {
            // If vault and reserve does not have enough balance, use it all and take rest from staked
            transferAmount = vaultAndReserveBalance;
            uint256 remainingAmount = assets - vaultAndReserveBalance;
            
            // Check for overflow, must never happen
            if (remainingAmount > curStakedBalance) {
                revert Overflow(remainingAmount, curStakedBalance);
            }

            // Update required values: vault and reserve balances are depleted, staking balance refund will be requested
            curStakedBalance -= remainingAmount;
            stakedBalance = curStakedBalance;
            curVaultBalance = 0;
            curReserveBalance = 0;
        }

        // Recalculate balances
        reserveBalance = curReserveBalance;
        vaultBalance = curVaultBalance;
        curTotalReserves = curStakedBalance + curVaultBalance + curReserveBalance;
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

    /// @dev Top-ups vault balance via Distributor.
    /// @param amount OLAS amount.
    function topUpVaultBalance(uint256 amount) external {
        if (msg.sender != distributor) {
            revert DistributorOnly(msg.sender, distributor);
        }

        asset.transferFrom(msg.sender, address(this), amount);
        vaultBalance += amount;

        emit VaultBalanceTopUpped(amount);
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
    /// @return curReserveBalance Current reserve balance.
    /// @return curTotalReserves Current total reserves.
    function calculateDepositBalances(uint256 assets) public view
        returns (uint256 curStakedBalance, uint256 curVaultBalance, uint256 curReserveBalance, uint256 curTotalReserves)
    {
        // topUpBalance is subtracted as it is passed as part of the assets value and already deposited
        // and accounted in reserveBalance via topUpReserveBalance() function call
        curStakedBalance = stakedBalance + assets - topUpBalance;

        // Get current vault balance
        curVaultBalance = vaultBalance;
        // Current reserve balance
        curReserveBalance = reserveBalance;

        // Update total assets
        curTotalReserves = curStakedBalance + curVaultBalance + reserveBalance;
    }

    /// @dev Previews deposit assets to shares amount.
    /// @notice This function can only be used for a strict amount of provided assets value.
    ///       It might not correlate with the Depository's `deposit()` function since the provided amount
    ///       could be changed due to other input parameters. For accurate correspondence with the Depository's
    ///       `deposit()` function use its static call directly.
    /// @param assets Deposited assets amount.
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        (, , , uint256 curTotalReserves) = calculateDepositBalances(assets);

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
        // Current staked balance
        curStakedBalance = stakedBalance;
        // Current vault balance
        curVaultBalance = vaultBalance;
        // Current reserve balance
        curReserveBalance = reserveBalance;

        // Total reserves
        curTotalReserves = curStakedBalance + curVaultBalance + curReserveBalance;
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