// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DefaultStakingProcessorL2} from "./DefaultStakingProcessorL2.sol";

// ERC20 token interface
interface IToken {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IBridge {
    // Contract: AMB Contract Proxy Home
    // Source: https://github.com/omni/tokenbridge-contracts/blob/908a48107919d4ab127f9af07d44d47eac91547e/contracts/upgradeable_contracts/arbitrary_message/MessageDelivery.sol#L22
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/amb-bridge
    /// @dev Requests message relay to the opposite network
    /// @param target Executor address on the other side.
    /// @param data Calldata passed to the executor on the other side.
    /// @param maxGasLimit Gas limit used on the other network for executing a message.
    /// @return Message Id.
    function requireToPassMessage(address target, bytes memory data, uint256 maxGasLimit) external returns (bytes32);

    // Contract: Omnibridge Multi-Token Mediator Proxy
    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/upgradeable_contracts/components/common/TokensRelayer.sol#L54
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/omnibridge
    function relayTokens(address token, address receiver, uint256 amount) external;

    // Source: https://github.com/omni/omnibridge/blob/c814f686487c50462b132b9691fd77cc2de237d3/contracts/interfaces/IAMB.sol#L14
    // Doc: https://docs.gnosischain.com/bridges/Token%20Bridge/amb-bridge#security-considerations-for-receiving-a-call
    function messageSender() external view returns (address);
}

/// @title GnosisStakingProcessorL2 - Smart contract for processing tokens and data received on Gnosis L2, and tokens sent back to L1.
contract GnosisStakingProcessorL2 is DefaultStakingProcessorL2 {
    // Bridge payload length
    uint256 public constant BRIDGE_PAYLOAD_LENGTH = 32;

    /// @dev GnosisTargetDispenserL2 constructor.
    /// @param _olas OLAS token address.
    /// @param _proxyFactory Service staking proxy factory address.
    /// @param _l2TokenRelayer L2 token relayer bridging contract address.
    /// @param _l2MessageRelayer L2 message relayer bridging contract address (AMBHomeProxy).
    /// @param _l1DepositProcessor L1 deposit processor address.
    /// @param _l1SourceChainId L1 source chain Id.
    constructor(
        address _olas,
        address _proxyFactory,
        address _l2TokenRelayer,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId
    )
        DefaultStakingProcessorL2(_olas, _proxyFactory, _l2TokenRelayer, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId)
    {}

    /// @dev Processes a message received from the AMB Contract Proxy (Home) contract.
    /// @param data Bytes message data sent from the AMB Contract Proxy (Home) contract.
    function receiveMessage(bytes memory data) external {
        // Get L1 deposit processor address
        address processor = IBridge(l2MessageRelayer).messageSender();

        // Process the data
        _receiveMessage(msg.sender, processor, data);
    }

    function relayToL1(uint256 olasAmount) external virtual override payable {
        // msg.value must be zero
        if (msg.value > 0) {
            revert();
        }

        IToken(olas).transferFrom(msg.sender, address(this), olasAmount);
        IToken(olas).approve(l2TokenRelayer, olasAmount);
        IBridge(l2TokenRelayer).relayTokens(olas, l1DepositProcessor, olasAmount);
    }
}