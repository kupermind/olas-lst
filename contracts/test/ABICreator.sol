// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Getting ABIs for the Gnosis Safe master copy and proxy contracts
import {GnosisSafe} from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeL2} from "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import {GnosisSafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import {DefaultCallbackHandler} from "@gnosis.pm/safe-contracts/contracts/handler/DefaultCallbackHandler.sol";
import {MultiSendCallOnly} from "@gnosis.pm/safe-contracts/contracts/libraries/MultiSendCallOnly.sol";

// Getting ABIs for registry contracts
import {OperatorWhitelist} from "../../lib/autonolas-registries/contracts/utils/OperatorWhitelist.sol";
import {ServiceRegistryL2} from "../../lib/autonolas-registries/contracts/ServiceRegistryL2.sol";
import {ServiceRegistryTokenUtility} from "../../lib/autonolas-registries/contracts/ServiceRegistryTokenUtility.sol";
import {ServiceManagerToken} from "../../lib/autonolas-registries/contracts/ServiceManagerToken.sol";
import {GnosisSafeMultisig} from "../../lib/autonolas-registries/contracts/multisigs/GnosisSafeMultisig.sol";
import {GnosisSafeSameAddressMultisig} from "../../lib/autonolas-registries/contracts/multisigs/GnosisSafeSameAddressMultisig.sol";
import {StakingVerifier} from "../../lib/autonolas-registries/contracts/staking/StakingVerifier.sol";
import {StakingFactory} from "../../lib/autonolas-registries/contracts/staking/StakingFactory.sol";
import {ERC20Token} from "../../lib/autonolas-registries/contracts/test/ERC20Token.sol";