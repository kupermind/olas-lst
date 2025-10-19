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
castArgs="$depositoryProxyAddress createAndActivateStakingModels(uint256[],address[],uint256[],uint256[]) [100,100,100,100] [0x9277fa41D459274462D235B3e0A547add2Ac4Be3,0xeC45dfE874d98a4654a068579C6ca7924543Ec1c,0x53aB2f67a5575f6360D39104cF129e1ACd9A97e4,0x2f11Dc30726923EB37373424fDcd14340FC273Ca] [20000000000000000000000,8000000000000000000000,4000000000000000000000,800000000000000000000] [20,50,100,500]"
#castArgs="$depositoryProxyAddress createAndActivateStakingModels(uint256[],address[],uint256[],uint256[]) [8453] [] [20000000000000000000000] [20]"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
