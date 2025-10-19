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

olasAddress=$(jq -r ".olasAddress" $globals)
depositoryProxyAddress=$(jq -r ".depositoryProxyAddress" $globals)
amount="30000000000000000000000"

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

echo "${green}Approve OLAS for DepositoryProxy${reset}"
castArgs="$olasAddress approve(address,uint256) $depositoryProxyAddress $amount"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"


# max: 20k, 8k, 4k, 800
chainIds="[100,100]"
stakingProxies="[0x9277fa41D459274462D235B3e0A547add2Ac4Be3,0x9277fa41D459274462D235B3e0A547add2Ac4Be3]"
#stakingProxies="[0x9277fa41D459274462D235B3e0A547add2Ac4Be3,0xeC45dfE874d98a4654a068579C6ca7924543Ec1c,0x53aB2f67a5575f6360D39104cF129e1ACd9A97e4,0x2f11Dc30726923EB37373424fDcd14340FC273Ca]"
#chainIds="[8453,8453]"
#stakingProxies="[,]"
bridgePayloads="[0x,0x]"
values="[0,0]"

echo "${green}Deposit OLAS for stOLAS${reset}"
castArgs="$depositoryProxyAddress deposit(uint256,uint256[],address[],bytes[],uint256[]) $amount $chainIds $stakingProxies $bridgePayloads $values"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
