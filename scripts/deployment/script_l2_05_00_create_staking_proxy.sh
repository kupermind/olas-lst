#!/bin/bash

# Check if $1 is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <network>"
  echo "Example: $0 base_mainnet"
  exit 1
fi

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 0
fi

# Read variables using jq
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

stakingFactoryAddress=$(jq -r ".stakingFactoryAddress" $globals)
stakingTokenLockedAddress=$(jq -r ".stakingTokenLockedAddress" $globals)
olasAddress=$(jq -r ".olasAddress" $globals)
serviceRegistryAddress=$(jq -r ".serviceRegistryAddress" $globals)
serviceRegistryTokenUtilityAddress=$(jq -r ".serviceRegistryTokenUtilityAddress" $globals)
stakingManagerProxyAddress=$(jq -r ".stakingManagerProxyAddress" $globals)
moduleActivityCheckerAddress=$(jq -r ".moduleActivityCheckerAddress" $globals)

livenessPeriod=$(jq -r ".livenessPeriod" $globals)
minStakingDeposit=$(jq -r ".minStakingDeposit" $globals)
maxNumServices=$(jq -r ".maxNumServices" $globals)
timeForEmissions=$(jq -r ".timeForEmissions" $globals)
rewardsPerSecond=$(jq -r ".rewardsPerSecond" $globals)

proxyData=$(cast calldata "initialize((uint256,uint256,uint256,uint256,uint256,address,address,address,address,address))" "($maxNumServices, $rewardsPerSecond, $minStakingDeposit, $livenessPeriod, $timeForEmissions, $serviceRegistryAddress, $serviceRegistryTokenUtilityAddress, $olasAddress, $stakingManagerProxyAddress, $moduleActivityCheckerAddress)")

# Check for Polygon keys only since on other networks those are not needed
if [ $chainId == 137 ]; then
  API_KEY=$ALCHEMY_API_KEY_MATIC
  if [ "$API_KEY" == "" ]; then
      echo "set ALCHEMY_API_KEY_MATIC env variable"
      exit 0
  fi
elif [ $chainId == 80002 ]; then
    API_KEY=$ALCHEMY_API_KEY_AMOY
    if [ "$API_KEY" == "" ]; then
        echo "set ALCHEMY_API_KEY_AMOY env variable"
        exit 0
    fi
fi

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

echo "${green}Create StakingProxy contract${reset}"
castArgs="$stakingFactoryAddress createStakingInstance(address,bytes) $stakingTokenLockedAddress $proxyData"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
stakingProxyAddress=$(echo "$result" | grep "topics" | sed "s/^logs *//" | jq -r '.[0].topics[2] | "0x" + (.[26:])')

echo "${green}StakingProxy deployed at: $stakingProxyAddress${reset}"

# Verify contract
contractName="StakingTokenLocked"
contractPath="contracts/l2/$contractName.sol:$contractName"
constructorArgs="$stakingTokenLockedAddress"
contractParams="$stakingProxyAddress $contractPath --constructor-args $(cast abi-encode "constructor(address)" $constructorArgs)"
echo "Verification contract params: $contractParams"

echo "${green}Verifying contract on Etherscan...${reset}"
forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

blockscoutURL=$(jq -r '.blockscoutURL' $globals)
if [ "$blockscoutURL" != "null" ]; then
  echo "${green}Verifying contract on Blockscout...${reset}"
  forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
fi
