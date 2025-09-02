#!/bin/bash

# Check if $1 is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <network>"
  echo "Example: $0 base_mainnet"
  exit 1
fi

# Get L2 network name: gnosis, base, etc.
networkL2=$2

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

stOLASAddress=$(jq -r ".stOLASAddress" $globals)
treasuryProxyAddress=$(jq -r ".treasuryProxyAddress" $globals)
amount="10000000000000000000000"

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

echo "${green}Approve stOLAS for TreasuryProxy${reset}"
castArgs="$stOLASAddress approve(address,uint256) $treasuryProxyAddress $amount"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"


#chainIds="[100]"
#stakingProxies="[0x90b043b4D4416cad893f62284bd545d1d55E5081]"
chainIds="[8453]"
stakingProxies="[0x71756B35E3ba7688C75A948EdCA5E040C7C2DDf4]"
bridgePayloads="[0x]"
values="[0]"

echo "${green}Request to withdraw stOLAS for OLAS${reset}"
castArgs="$treasuryProxyAddress requestToWithdraw(uint256,uint256[],address[],bytes[],uint256[]) $amount $chainIds $stakingProxies $bridgePayloads $values"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
