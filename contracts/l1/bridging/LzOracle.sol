// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { OAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { ReadCodecV1, EVMCallRequestV1 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { OAppRead } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppRead.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {StakingModel} from "../Depository.sol";
import {InstanceParams} from "@registries/contracts/staking/StakingFactory.sol";

interface IStakingFactory {
    /// @dev Gets InstanceParams struct for a specified staking proxy
    /// @param stakingProxy Staking proxy address.
    function mapInstanceParams(address stakingProxy) external view returns (InstanceParams memory);
}

interface IStakingProxy {
    /// @dev Gets maximum number of staking services.
    function maxNumServices() external view returns (uint256);
    /// @dev Gets minimum service staking deposit value required for staking.
    function minStakingDeposit() external view returns (uint256);
    /// @dev Gets token rewards.
    function availableRewards() external view returns (uint256);
}

interface IDepository {
    /// @dev Gets staking model struct.
    /// @param stakingModelId Staking model Id.
    function mapStakingModels(uint256 stakingModelId) external view returns (StakingModel memory);

    /// @dev Creates and activates staking model via lzRead proofs.
    /// @param chainId Chain Id.
    /// @param stakingProxy Corresponding staking proxy address.
    /// @param stakeLimitPerSlot Corresponding staking limit per each staking slot.
    /// @param numSlots Corresponding number of staking slots.
    function LzCreateAndActivateStakingModel(uint256 chainId, address stakingProxy, uint256 stakeLimitPerSlot,
        uint256 numSlots) external;
}

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero value.
error ZeroValue();

/// @dev Wrong length of arrays.
error WrongArrayLength();

/// @dev Staking model already exists.
/// @param stakingModelId Staking model Id.
error StakingModelAlreadyExists(uint256 stakingModelId);

struct AccountChainIdMsgType {
    address account;
    uint32 chainId;
    uint16 msgType;
}


/// @title LzOracle - Smart contract for LayerZero oracle.
contract LzOracle is OAppRead, OAppOptionsType3 {
    event LzCreateAndActivateStakingModelProcessed(bytes32 indexed guid, uint256 chainId, address indexed stakingProxy,
        uint256 stakeLimitPerSlot, uint256 maxNumServices);
    event LzCreateAndActivateStakingModelInitiated(bytes32 indexed guid, uint256 chainId, address indexed stakingProxy);

    /// lzRead responses are sent from arbitrary channels with Endpoint IDs in the range of
    /// `eid > 4294965694` (which is `type(uint32).max - 1600`).
    uint32 public constant READ_CHANNEL_EID_THRESHOLD = 4294965694;
    // lzRead specific channel: https://docs.layerzero.network/v2/deployments/read-contracts
    uint32 public constant READ_CHANNEL = 4294967295;
    // Message type for read create operation
    uint16 public constant READ_TYPE_CREATE = 1;
    // Message type for read close operation
    uint16 public constant READ_TYPE_CLOSE = 2;

    // Depository address
    address public immutable depository;

    // Mapping of EVM chain Id => (stakingFactory address, chainId in LZ format, msg type)
    mapping(uint256 => AccountChainIdMsgType) public mapStakingFactoryLzChainIds;
    // Mapping of Guid => (stakingProxy address, EVM chainId, msg type)
    mapping(bytes32 => AccountChainIdMsgType) public mapUidStakingProxyChainIds;

    constructor(
        address _endpoint,
        uint256[] memory _chainIds,
        address[] memory _stakingFactories,
        uint256[] memory _lzChainIds
    )
        OAppRead(_endpoint, msg.sender) Ownable(msg.sender)
    {
        setChainIdStakingFactoryLzChainIds(_chainIds, _stakingFactories, _lzChainIds);
    }

//    /// @notice Thanks for making it virtual :).
//    function _payNative(uint256 _nativeFee) internal override returns (uint256 nativeFee) {
//        require(msg.value >= _nativeFee, "NotEnoughNative");
//        return _nativeFee;
//    }

    /// @notice Internal function to handle message responses.
    /// @dev origin The origin information.
    /// @dev guid The unique identifier for the received message (unused in this implementation).
    /// @param message The encoded message data.
    /// @dev executor The executor address (unused in this implementation).
    /// @dev extraData Additional data (unused in this implementation).
    function _lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address /* executor */,
        bytes calldata /* extraData */
    ) internal override {
        require(origin.srcEid > READ_CHANNEL_EID_THRESHOLD, "LZ Read receives only");

        // Get chainId and stakingProxy address corresponding to guid
        AccountChainIdMsgType memory accountChainIdMsgType = mapUidStakingProxyChainIds[guid];

        // Check for message type
        if (accountChainIdMsgType.msgType == READ_TYPE_CREATE) {
            // Decode obtained data
            (InstanceParams memory instanceParams, uint256 maxNumServices, uint256 minStakingDeposit,
                uint256 availableRewards) = abi.decode(message, (InstanceParams, uint256, uint256, uint256));

            // Check for correctness of parameters
            if (!instanceParams.isEnabled || availableRewards == 0) {
                revert ();
            }

            // Considering 1 agent per service: deposit + operator bond = 2 * minStakingDeposit
            uint256 stakeLimitPerSlot = 2 * minStakingDeposit;
            IDepository(depository).LzCreateAndActivateStakingModel(accountChainIdMsgType.chainId, accountChainIdMsgType.account,
                stakeLimitPerSlot, maxNumServices);

            emit LzCreateAndActivateStakingModelProcessed(guid, accountChainIdMsgType.chainId, accountChainIdMsgType.account,
                stakeLimitPerSlot, maxNumServices);
        } else if (accountChainIdMsgType.msgType == READ_TYPE_CLOSE) {
            // Decode obtained data
            uint256 availableRewards = abi.decode(message, (uint256));

            // Check for correctness of parameters
            if (availableRewards > 0) {
                revert ();
            }

            // TODO emit
        } else {
            // This must never happen
            revert();
        }
    }

    /// @dev Constructs a command to query stakingProxy info on a specified chain Id.
    /// @param stakingProxy Staking proxy address.
    /// @param stakingFactory Staking factory address.
    /// @param lzChainId Chain Id in LZ format.
    /// @return Encoded lzRead request.
    function _getCmdCreateAndActivateStakingModel(
        address stakingProxy,
        address stakingFactory,
        uint256 lzChainId
    ) internal view returns (bytes memory) {
        // Allocate required number of read requests
        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](4);

        // Get instance params of stakingProxy
        readRequests[0] = EVMCallRequestV1({
            appRequestLabel: uint16(0),
            targetEid: uint32(lzChainId),
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 15,
            to: stakingFactory,
            callData: abi.encodeCall(IStakingFactory.mapInstanceParams, (stakingProxy))
        });

        // Get max number of services in stakingProxy
        readRequests[1] = EVMCallRequestV1({
            appRequestLabel: uint16(0),
            targetEid: uint32(lzChainId),
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 15,
            to: stakingProxy,
            callData: abi.encodeCall(IStakingProxy.maxNumServices, ())
        });

        // Get min staking deposit in stakingProxy
        readRequests[2] = EVMCallRequestV1({
            appRequestLabel: uint16(0),
            targetEid: uint32(lzChainId),
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 15,
            to: stakingProxy,
            callData: abi.encodeCall(IStakingProxy.minStakingDeposit, ())
        });

        // Get stakingProxy available rewards
        readRequests[3] = EVMCallRequestV1({
            appRequestLabel: uint16(0),
            targetEid: uint32(lzChainId),
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 15,
            to: stakingProxy,
            callData: abi.encodeCall(IStakingProxy.availableRewards, ())
        });

        return ReadCodecV1.encode(0, readRequests);
    }

    function lzCreateAndActivateStakingModel(uint256 chainId, address stakingProxy, bytes calldata options) external payable {
        // Push a pair of key defining variables into one key: chainId | stakingProxy
        // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
        uint256 stakingModelId = uint256(uint160(stakingProxy));
        stakingModelId |= chainId << 160;

        // Get staking model struct
        StakingModel memory stakingModel = IDepository(depository).mapStakingModels(stakingModelId);

        // Check for existing staking model
        if (stakingModel.supply > 0) {
            revert StakingModelAlreadyExists(stakingModelId);
        }

        AccountChainIdMsgType memory accountChainId = mapStakingFactoryLzChainIds[chainId];
        bytes memory payload = _getCmdCreateAndActivateStakingModel(stakingProxy, accountChainId.account,
            accountChainId.chainId);

        // TODO Figure out the correct quote check
        MessagingFee memory fee = _quote(READ_CHANNEL, payload, options, false);
        require(msg.value >= fee.nativeFee);

        MessagingReceipt memory receipt =
            _lzSend(
                READ_CHANNEL,
                payload,
                combineOptions(READ_CHANNEL, READ_TYPE_CREATE, options),
                MessagingFee(msg.value, 0),
                payable(tx.origin)
            );

        mapUidStakingProxyChainIds[receipt.guid] = AccountChainIdMsgType(stakingProxy, uint32(chainId), READ_TYPE_CREATE);

        emit LzCreateAndActivateStakingModelInitiated(receipt.guid, chainId, stakingProxy);
    }

    function setChainIdStakingFactoryLzChainIds(
        uint256[] memory chainIds,
        address[] memory stakingFactories,
        uint256[] memory lzChainIds
    ) public onlyOwner {
        // Check for array length correctness
        if (chainIds.length == 0 || chainIds.length != stakingFactories.length || chainIds.length != lzChainIds.length) {
            revert WrongArrayLength();
        }

        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Check for zero values
            if (chainIds[i] == 0 || lzChainIds[i] == 0) {
                revert ZeroValue();
            }

            // Check for zero address
            if (stakingFactories[i] == address(0)) {
                revert ZeroAddress();
            }

            mapStakingFactoryLzChainIds[chainIds[i]] = AccountChainIdMsgType(stakingFactories[i], uint32(lzChainIds[i]), 0);
        }
    }
}