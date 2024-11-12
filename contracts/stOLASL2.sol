// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {stOLAS, MinterOnly} from "./stOLAS.sol";

/// @title stOLASL2 - Smart contract for the stOLAS token on L2.
contract stOLASL2 is stOLAS {

    constructor() stOLAS() {}

    /// @dev Burns stOLASL2 tokens.
    /// @param amount stOLASL2 token amount to burn.
    function burn(uint256 amount) external {
        // Access control
        if (msg.sender != minter) {
            revert MinterOnly(msg.sender, minter);
        }

        _burn(msg.sender, amount);
    }
}