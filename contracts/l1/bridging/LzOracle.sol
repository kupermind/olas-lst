// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {ReadCodecV1, EVMCallRequestV1} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import {OAppRead} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppRead.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    StakingModel,
    StakingModelAlreadyExists,
    WrongArrayLength,
    WrongStakingModel,
    ZeroAddress,
    ZeroValue
} from "../Depository.sol";

interface IStakingHelper {
    /// @dev Gets stakingProxy info.
    /// @param stakingProxy Staking proxy address.
    /// @return bytecodeHash Staking proxy implementation bytecode hash.
    /// @return isEnabled Staking proxy status flag.
    /// @return maxNumSlots Max number of slots in staking proxy.
    /// @return minStakingDeposit Minimum deposit value required for service staking.
    /// @return availableRewards Staking proxy available rewards.
    function getStakingInfo(address stakingProxy)
        external
        view
        returns (
            bytes32 bytecodeHash,
            bool isEnabled,
            uint256 maxNumSlots,
            uint256 minStakingDeposit,
            uint256 availableRewards
        );
}

interface IStakingProxy {
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
    function LzCreateAndActivateStakingModel(
        uint256 chainId,
        address stakingProxy,
        uint256 stakeLimitPerSlot,
        uint256 numSlots
    ) external;

    /// @dev Closes staking model via lzRead proofs.
    /// @param chainId Chain Id.
    /// @param stakingProxy Corresponding staking proxy address.
    function LzCloseStakingModel(uint256 chainId, address stakingProxy) external;
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

struct AccountChainIdMsgType {
    address account;
    uint32 chainId;
    uint16 msgType;
}

/// @title LzOracle - Smart contract for LayerZero oracle.
contract LzOracle is OAppRead, OAppOptionsType3 {
    event LzCreateAndActivateStakingModelProcessed(
        bytes32 indexed guid,
        uint256 chainId,
        address indexed stakingProxy,
        uint256 stakeLimitPerSlot,
        uint256 maxNumServices
    );
    event LzCloseStakingModelProcessed(bytes32 indexed guid, uint256 chainId, address indexed stakingProxy);
    event LzCreateAndActivateStakingModelInitiated(bytes32 indexed guid, uint256 chainId, address indexed stakingProxy);
    event LzCloseStakingModelInitiated(bytes32 indexed guid, uint256 chainId, address indexed stakingProxy);

    /// lzRead responses are sent from arbitrary channels with Endpoint IDs in the range of
    /// `eid > 4294965694` (which is `type(uint32).max - 1600`).
    uint32 public constant READ_CHANNEL_EID_THRESHOLD = 4294965694;
    // lzRead specific channel: https://docs.layerzero.network/v2/deployments/read-contracts
    uint32 public constant READ_CHANNEL = 4294967295;
    // Message type for read create operation
    uint16 public constant READ_TYPE_CREATE = 1;
    // Message type for read close operation
    uint16 public constant READ_TYPE_CLOSE = 2;

    // Staking implementation bytecode hash
    bytes32 public immutable stakingImplementationBytecodeHash;
    // Depository address
    address public immutable depository;

    // Mapping of EVM chain Id => (stakingHelper address, chainId in LZ format, msg type)
    mapping(uint256 => AccountChainIdMsgType) public mapStakingHelperLzChainIds;
    // Mapping of Guid => (stakingProxy address, EVM chainId, msg type)
    mapping(bytes32 => AccountChainIdMsgType) public mapUidStakingProxyChainIds;

    /// @dev LzOracle constructor.
    /// @param _endpoint LZ endpoint address.
    /// @param _depository Depository address.
    /// @param _stakingImplementationBytecodeHash Staking implementation contract bytecode hash.
    /// @param _chainIds supported EVM chain Ids.
    /// @param _stakingHelpers Corresponding staking helper addresses.
    /// @param _lzChainIds Corresponding LZ format chain Ids.
    constructor(
        address _endpoint,
        address _depository,
        bytes32 _stakingImplementationBytecodeHash,
        uint256[] memory _chainIds,
        address[] memory _stakingHelpers,
        uint256[] memory _lzChainIds
    ) OAppRead(_endpoint, msg.sender) Ownable(msg.sender) {
        // Check for zero address
        if (_depository == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero value
        if (_stakingImplementationBytecodeHash == 0) {
            revert ZeroValue();
        }

        depository = _depository;
        stakingImplementationBytecodeHash = _stakingImplementationBytecodeHash;

        // Set chain Ids and corresponding staking helpers
        setChainIdStakingHelperLzChainIds(_chainIds, _stakingHelpers, _lzChainIds);
    }

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
        address, /* executor */
        bytes calldata /* extraData */
    ) internal override {
        require(origin.srcEid > READ_CHANNEL_EID_THRESHOLD, "LZ Read receives only");

        // Get chainId and stakingProxy address corresponding to guid
        AccountChainIdMsgType memory accountChainIdMsgType = mapUidStakingProxyChainIds[guid];

        // Push a pair of key defining variables into one key: chainId | stakingProxy
        // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
        uint256 stakingModelId = uint256(uint160(accountChainIdMsgType.account));
        stakingModelId |= accountChainIdMsgType.chainId << 160;

        // Check for message type
        if (accountChainIdMsgType.msgType == READ_TYPE_CREATE) {
            // Decode obtained data
            (
                bytes32 bytecodeHash,
                bool isEnabled,
                uint256 maxNumServices,
                uint256 minStakingDeposit,
                uint256 availableRewards
            ) = abi.decode(message, (bytes32, bool, uint256, uint256, uint256));

            // Check for correctness of parameters for staking proxy
            if (!isEnabled || availableRewards == 0 || bytecodeHash != stakingImplementationBytecodeHash) {
                revert WrongStakingModel(stakingModelId);
            }

            // Considering 1 agent per service: deposit + operator bond = 2 * minStakingDeposit
            uint256 stakeLimitPerSlot = 2 * minStakingDeposit;
            IDepository(depository).LzCreateAndActivateStakingModel(
                accountChainIdMsgType.chainId, accountChainIdMsgType.account, stakeLimitPerSlot, maxNumServices
            );

            emit LzCreateAndActivateStakingModelProcessed(
                guid, accountChainIdMsgType.chainId, accountChainIdMsgType.account, stakeLimitPerSlot, maxNumServices
            );
        } else if (accountChainIdMsgType.msgType == READ_TYPE_CLOSE) {
            // Decode obtained data
            uint256 availableRewards = abi.decode(message, (uint256));

            // Check for correctness of parameters
            if (availableRewards > 0) {
                revert WrongStakingModel(stakingModelId);
            }

            IDepository(depository).LzCloseStakingModel(accountChainIdMsgType.chainId, accountChainIdMsgType.account);

            emit LzCloseStakingModelProcessed(guid, accountChainIdMsgType.chainId, accountChainIdMsgType.account);
        } else {
            // This must never happen
            revert WrongStakingModel(stakingModelId);
        }
    }

    /// @dev Constructs a command to query stakingHelper to fetch stakingProxy info on a specified chain Id.
    /// @param stakingProxy Staking proxy address.
    /// @param stakingHelper Staking helper address.
    /// @param lzChainId Chain Id in LZ format.
    /// @return Encoded lzRead request.
    function _cmdGetStakingInfo(address stakingProxy, address stakingHelper, uint256 lzChainId)
        internal
        view
        returns (bytes memory)
    {
        // Allocate required number of read requests
        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](1);

        // Get stakingProxy info
        readRequests[0] = EVMCallRequestV1({
            appRequestLabel: uint16(0),
            targetEid: uint32(lzChainId),
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 15,
            to: stakingHelper,
            callData: abi.encodeCall(IStakingHelper.getStakingInfo, (stakingProxy))
        });

        return ReadCodecV1.encode(0, readRequests);
    }

    /// @dev Constructs a command to query stakingProxy available rewards on a specified chain Id.
    /// @param stakingProxy Staking proxy address.
    /// @param lzChainId Chain Id in LZ format.
    /// @return Encoded lzRead request.
    function _cmdGetAvailableRewards(address stakingProxy, uint256 lzChainId) internal view returns (bytes memory) {
        // Allocate required number of read requests
        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](1);

        // Get stakingProxy info
        readRequests[0] = EVMCallRequestV1({
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

    /// @dev Creates and activates staking model via LzRead.
    /// @param chainId EVM chain Id.
    /// @param stakingProxy Staking proxy address.
    /// @param options LZ message options.
    function lzCreateAndActivateStakingModel(uint256 chainId, address stakingProxy, bytes calldata options)
        external
        payable
        onlyOwner
    {
        // Push a pair of key defining variables into one key: chainId | stakingProxy
        // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
        uint256 stakingModelId = uint256(uint160(stakingProxy));
        stakingModelId |= chainId << 160;

        // Get staking model struct
        StakingModel memory stakingModel = IDepository(depository).mapStakingModels(stakingModelId);

        // Check for existing staking model: supply must be zero as the model does not exist
        if (stakingModel.supply > 0) {
            revert StakingModelAlreadyExists(stakingModelId);
        }

        AccountChainIdMsgType memory accountChainId = mapStakingHelperLzChainIds[chainId];
        // Check for existing struct
        if (accountChainId.account == address(0)) {
            revert ZeroAddress();
        }

        // Get lzRead payload
        bytes memory payload = _cmdGetStakingInfo(stakingProxy, accountChainId.account, accountChainId.chainId);

        // Get message options fee
        bytes memory messageOptions = combineOptions(READ_CHANNEL, READ_TYPE_CREATE, options);
        MessagingFee memory fee = _quote(READ_CHANNEL, payload, messageOptions, false);
        require(msg.value >= fee.nativeFee);

        MessagingReceipt memory receipt = _lzSend(
            READ_CHANNEL,
            payload,
            messageOptions,
            MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 }),
            payable(msg.sender)
        );

        mapUidStakingProxyChainIds[receipt.guid] =
            AccountChainIdMsgType({ account: stakingProxy, chainId: uint32(chainId), msgType: READ_TYPE_CREATE });

        emit LzCreateAndActivateStakingModelInitiated(receipt.guid, chainId, stakingProxy);
    }

    /// @dev Closes staking model via LzRead.
    /// @param chainId EVM chain Id.
    /// @param stakingProxy Staking proxy address.
    /// @param options LZ message options.
    function lzCloseStakingModel(uint256 chainId, address stakingProxy, bytes calldata options) external payable onlyOwner {
        // Push a pair of key defining variables into one key: chainId | stakingProxy
        // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
        uint256 stakingModelId = uint256(uint160(stakingProxy));
        stakingModelId |= chainId << 160;

        // Get staking model struct
        StakingModel memory stakingModel = IDepository(depository).mapStakingModels(stakingModelId);

        // Check for existing staking model: supply must be non-zero
        if (stakingModel.supply == 0) {
            revert WrongStakingModel(stakingModelId);
        }

        AccountChainIdMsgType memory accountChainId = mapStakingHelperLzChainIds[chainId];
        bytes memory payload = _cmdGetAvailableRewards(stakingProxy, accountChainId.chainId);

        // Get message options fee
        bytes memory messageOptions = combineOptions(READ_CHANNEL, READ_TYPE_CLOSE, options);
        MessagingFee memory fee = _quote(READ_CHANNEL, payload, messageOptions, false);
        require(msg.value >= fee.nativeFee);

        MessagingReceipt memory receipt = _lzSend(
            READ_CHANNEL,
            payload,
            messageOptions,
            MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 }),
            payable(msg.sender)
        );

        mapUidStakingProxyChainIds[receipt.guid] = AccountChainIdMsgType({ account: stakingProxy, chainId: uint32(chainId), msgType: READ_TYPE_CLOSE });

        emit LzCloseStakingModelInitiated(receipt.guid, chainId, stakingProxy);
    }

    /// @dev Sets correspondence between EVM chain Id, staking helper addresses and LZ format chain Ids.
    /// @param chainIds supported EVM chain Ids.
    /// @param stakingHelpers Corresponding staking helper addresses.
    /// @param lzChainIds Corresponding LZ format chain Ids.
    function setChainIdStakingHelperLzChainIds(
        uint256[] memory chainIds,
        address[] memory stakingHelpers,
        uint256[] memory lzChainIds
    ) public onlyOwner {
        // Check for array length correctness
        if (chainIds.length == 0 || chainIds.length != stakingHelpers.length || chainIds.length != lzChainIds.length) {
            revert WrongArrayLength();
        }

        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Check for zero values
            if (chainIds[i] == 0 || lzChainIds[i] == 0) {
                revert ZeroValue();
            }

            // Check for zero address
            if (stakingHelpers[i] == address(0)) {
                revert ZeroAddress();
            }

            mapStakingHelperLzChainIds[chainIds[i]] = AccountChainIdMsgType({ account: stakingHelpers[i], chainId: uint32(lzChainIds[i]), msgType: 0 });
        }
    }
}
