// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IUniswapV3} from "../interfaces/IUniswapV3.sol";

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

    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);
}

interface ITreasury {
    function updateReserves() external returns (uint256);
}

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero value when it has to be different from zero.
error ZeroValue();

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Only `treasury` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param treasury Required treasury address.
error TreasuryOnly(address sender, address treasury);

/// @dev The contract is already initialized.
error AlreadyInitialized();

// @dev Reentrancy guard.
error ReentrancyGuard();

/// @title LiquidityManager - Smart contract for managing different token liquidity
contract LiquidityManager {
    // Uniswap V3 fee tier of 1%
    uint24 public constant FEE_TIER = 10_000;
    /// The minimum tick that corresponds to a selected fee tier
    int24 public constant MIN_TICK = -887200;
    /// The maximum tick that corresponds to a selected fee tier
    int24 public constant MAX_TICK = -MIN_TICK;

    // OLAS address
    address public immutable olas;
    // Treasury address
    address public immutable treasury;
    // Uniswap V3 position manager
    address public immutable uniV3PositionManager;

    // Owner address
    address public owner;
    // Reentrancy lock
    uint256 internal _locked;

    /// @dev LiquidityManager constructor.
    /// @param _olas OLAS address.
    /// @param _treasury Treasury address.
    /// @param _uniV3PositionManager Uniswap V3 position manager address.
    constructor(address _olas, address _treasury, address _uniV3PositionManager) {
        // Check for the zero address
        if (_olas == address(0) || _treasury == address(0) || _uniV3PositionManager == address(0)) {
            revert ZeroAddress();
        }

        olas = _olas;
        treasury = _treasury;
        uniV3PositionManager = _uniV3PositionManager;
    }

    /// @dev LiquidityManager initializer.
    function initialize() external{
        // Check for already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        owner = msg.sender;
        _locked = 1;
    }

    function _depositOlasToTreasury() internal {
        // Send OLAS back to treasury
        uint256 olasBalance = IToken(olas).balanceOf(address(this));
        if (olasBalance > 0) {
            // Transfer OLAS for treasury
            IToken(olas).transfer(treasury, olasBalance);
            ITreasury(treasury).updateReserves();
        }
    }

    // TODO Make same function accessed by owner to create pairs from this contract balances
    /// @dev Adds UniswapV3 liquidity.
    /// @param token0 Token 0.
    /// @param token1 Token 1.
    /// @param amount0 Amount 0.
    /// @param amount1 MAmount 1.
    /// @return positionId LP position token Id.
    /// @return liquidity Obtained LP liquidity.
    function addUniswapLiquidity(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 positionId, uint256 liquidity) {
        // Ensure token order matches Uniswap convention
        (token0, token1, amount0, amount1) = token0 < token1 ?
            (token0, token1, amount0, amount1) : (token1, token0, amount1, amount0);

        // Get factory address
        address factory = IUniswapV3(uniV3PositionManager).factory();
        // Verify that pool does not exist
        address pool = IUniswapV3(factory).getPool(token0, token1, FEE_TIER);
        if (pool == address(0)) {
            revert ZeroAddress();
        }

        // Transfer tokens
        IToken(token0).transferFrom(msg.sender, address(this), amount0);
        IToken(token1).transferFrom(msg.sender, address(this), amount1);

        // Approve tokens for router
        IToken(token0).approve(uniV3PositionManager, amount0);
        IToken(token1).approve(uniV3PositionManager, amount1);

        // Add native token + meme token liquidity
        IUniswapV3.MintParams memory params = IUniswapV3.MintParams({
            token0: token0,
            token1: token1,
            fee: FEE_TIER,
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0, // Accept any amount of token0
            amount1Min: 0, // Accept any amount of token1
            recipient: address(this),
            deadline: block.timestamp
        });

        (positionId, liquidity, , ) = IUniswapV3(uniV3PositionManager).mint(params);

        _depositOlasToTreasury();
    }

    /// @dev Collects all accumulated LP fees and sends OLAS to treasury.
    /// @param positionIds Set of LP position Ids.
    function collectFees(uint256[] memory positionIds) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Traverse to collect fees
        for (uint256 i = 0; i < positionIds.length; ++i) {
            // TODO
            // Get position tokens
            //(uint256 token0, uint256 token1) = IUniswapV3(uniV3PositionManager).getTokens(positionIds[i]);

            // TODO
            // Check current pool prices
            //IBuyBackBurner(buyBackBurner).checkPoolPrices(token0, token1, uniV3PositionManager, FEE_TIER);

            IUniswapV3.CollectParams memory params = IUniswapV3.CollectParams({
                tokenId: positionIds[i],
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

            // Get corresponding token fees
            (uint256 amount0, uint256 amount1) = IUniswapV3(uniV3PositionManager).collect(params);
            if (amount0 == 0 && amount1 == 0) {
                revert ZeroValue();
            }
        }

        _depositOlasToTreasury();

        _locked = 1;
    }

    function withdraw(address token, address to) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        if (token == olas) {
            revert();
        }

        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        uint256 tokenBalance = IToken(token).balanceOf(address(this));
        if (tokenBalance > 0) {
            // TODO Check result?
            // Transfer tokens
            IToken(token).transfer(to, tokenBalance);
        }

        _locked = 1;
    }
}
