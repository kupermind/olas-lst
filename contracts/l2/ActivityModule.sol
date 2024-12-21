// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Zero address.
error ZeroAddress();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @title ActivityModule - Smart contract for multisig activity tracking
contract ActivityModule {
    event ActivityIncreased(uint256 activityChange);

    // Rewards collector address
    address public immutable collector;

    // Activity tracker
    uint256 public activityNonce;
    // Multisig address
    address public multisig;

    constructor(address _collector) {
        collector = _collector;
    }

    function initialize(address _multisig) external {
        if (multisig != address(0)) {
            revert AlreadyInitialized();
        }

        // Check for zero address
        if (_multisig == address(0)) {
            revert ZeroAddress();
        }

        multisig = _multisig;

        // TODO: Call multisig to enable module as address(this)
    }

    function execute(bytes memory) external {
        activityNonce++;

        emit ActivityIncreased(1);
    }

    function claim(uint256 serviceId) external {
        IStaking(stakingInstance).claim(serviceId);

        uint256 balance = IToken(olas).balanceOf(multisig);

        if (balance > 0) {
            multisig.execute(transfer(olas), collector, balance);
        }
    }
}
