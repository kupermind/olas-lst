// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Getting ABIs for the Gnosis Safe master copy and proxy contracts
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/handler/DefaultCallbackHandler.sol";
import "@gnosis.pm/safe-contracts/contracts/libraries/MultiSendCallOnly.sol";

// Getting ABIs for registry contracts
import {OperatorWhitelist} from "../../lib/autonolas-registries/contracts/utils/OperatorWhitelist.sol";
import {ServiceRegistryL2} from "../../lib/autonolas-registries/contracts/ServiceRegistryL2.sol";
import {ServiceRegistryTokenUtility} from "../../lib/autonolas-registries/contracts/ServiceRegistryTokenUtility.sol";
import {ServiceManagerToken} from "../../lib/autonolas-registries/contracts/ServiceManagerToken.sol";
import {GnosisSafeMultisig} from "../../lib/autonolas-registries/contracts/multisigs/GnosisSafeMultisig.sol";
import {GnosisSafeSameAddressMultisig} from "../../lib/autonolas-registries/contracts/multisigs/GnosisSafeSameAddressMultisig.sol";
import {StakingFactory} from "../../lib/autonolas-registries/contracts/staking/StakingFactory.sol";