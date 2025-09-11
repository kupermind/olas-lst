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

olasAddress=$(jq -r ".olasAddress" $globals)
stakingProxyAddress=$(jq -r ".stakingProxyAddresses.[1]" $globals)
amount="10000000000000000000000"

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

echo "${green}Approve OLAS for StakingProxy${reset}"
castArgs="$olasAddress approve(address,uint256) $stakingProxyAddress $amount"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"

echo "${green}Fund StakingProxy contract${reset}"
castArgs="$stakingProxyAddress deposit(uint256) $amount"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
