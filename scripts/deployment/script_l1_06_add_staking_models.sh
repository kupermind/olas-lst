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

depositoryProxyAddress=$(jq -r ".depositoryProxyAddress" $globals)

# Getting L1 API key
if [ $chainId == 1 ]; then
  API_KEY=$ALCHEMY_API_KEY_MAINNET
  if [ "$API_KEY" == "" ]; then
      echo "set ALCHEMY_API_KEY_MAINNET env variable"
      exit 0
  fi
elif [ $chainId == 11155111 ]; then
    API_KEY=$ALCHEMY_API_KEY_SEPOLIA
    if [ "$API_KEY" == "" ]; then
        echo "set ALCHEMY_API_KEY_SEPOLIA env variable"
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

echo "${green}Add staking models${reset}"
castArgs="$depositoryProxyAddress createAndActivateStakingModels(uint256[],address[],uint256[],uint256[]) [100,100,100,100] [0x940fb482A821B666CCCE93723d1C6c9359785150,0xcf98Cd2B423c045dc2A1259A4f02291910b64E74,0x05b6e1341877F728fa460fc1A78FB3f699FE62EB,0x16DAeAE9582B80F1c07E1b26cADCf33cE4e7D1d7] [20000000000000000000000,8000000000000000000000,4000000000000000000000,800000000000000000000] [20,50,100,500]"
#castArgs="$depositoryProxyAddress createAndActivateStakingModels(uint256[],address[],uint256[],uint256[]) [8453] [0x71756B35E3ba7688C75A948EdCA5E040C7C2DDf4] [20000000000000000000000] [20]"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
