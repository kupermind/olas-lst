#!/bin/bash

# Check if $1 is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <network_l1> <network_l2>"
  echo "Example: $0 eth_mainnet base_mainnet"
  exit 1
fi

# Check if $2 is provided
if [ -z "$2" ]; then
  echo "Usage: $0 <network_l1> <network_l2>"
  echo "Example: $0 eth_mainnet base_mainnet"
  exit 1
fi

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get globals files
globalsL1="$(dirname "$0")/globals_$1.json"
if [ ! -f $globalsL1 ]; then
  echo "${red}!!! $globalsL1 is not found${reset}"
  exit 0
fi

globalsL2="$(dirname "$0")/globals_$2.json"
if [ ! -f $globalsL2 ]; then
  echo "${red}!!! $globalsL2 is not found${reset}"
  exit 0
fi

# Read variables using jq
chainIdL1=$(jq -r '.chainId' $globalsL1)
networkURLL1=$(jq -r '.networkURL' $globalsL1)
chainIdL2=$(jq -r '.chainId' $globalsL2)
networkURLL2=$(jq -r '.networkURL' $globalsL2)

# Getting L1 API key
if [ $chainIdL1 == 1 ]; then
  API_KEY=$ALCHEMY_API_KEY_MAINNET
  if [ "$API_KEY" == "" ]; then
      echo "set ALCHEMY_API_KEY_MAINNET env variable"
      exit 0
  fi
elif [ $chainIdL1 == 11155111 ]; then
    API_KEY=$ALCHEMY_API_KEY_SEPOLIA
    if [ "$API_KEY" == "" ]; then
        echo "set ALCHEMY_API_KEY_SEPOLIA env variable"
        exit 0
    fi
fi

olasAddressL1=$(jq -r ".olasAddress" $globalsL1)
stOLASAddress=$(jq -r ".stOLASAddress" $globalsL1)
lockProxyAddress=$(jq -r ".lockProxyAddress" $globalsL1)
distributorProxyAddress=$(jq -r ".distributorProxyAddress" $globalsL1)
unstakeRelayerProxyAddress=$(jq -r ".unstakeRelayerProxyAddress" $globalsL1)
depositoryProxyAddress=$(jq -r ".depositoryProxyAddress" $globalsL1)
treasuryProxyAddress=$(jq -r ".treasuryProxyAddress" $globalsL1)

olasAddressL2=$(jq -r ".olasAddress" $globalsL2)
collectorProxyAddress=$(jq -r ".collectorProxyAddress" $globalsL2)
stakingManagerProxyAddress=$(jq -r ".stakingManagerProxyAddress" $globalsL2)

castSendHeader="cast call --rpc-url $networkURLL1$API_KEY"

echo "${green}Checking stOLAS${reset}"
# Depository
castArgs="$stOLASAddress depository()(address)"
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
if [ $result != $depositoryProxyAddress ]; then
  echo "${red}!!! Depository address is incorrect!${reset}"
  echo "${red}!!! Fetched address:$result${reset}"
  echo "${red}!!! Expected address:$depositoryProxyAddress${reset}"
  exit 0
fi
# Treasury
castArgs="$stOLASAddress treasury()(address)"
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
if [ $result != $treasuryProxyAddress ]; then
  echo "${red}!!! Treasury address is incorrect!${reset}"
  echo "${red}!!! Fetched address:$result${reset}"
  echo "${red}!!! Expected address:$treasuryProxyAddress${reset}"
  exit 0
fi
# Distributor
castArgs="$stOLASAddress distributor()(address)"
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
if [ $result != $distributorProxyAddress ]; then
  echo "${red}!!! Distributor address is incorrect!${reset}"
  echo "${red}!!! Fetched address:$result${reset}"
  echo "${red}!!! Expected address:$distributorProxyAddress${reset}"
  exit 0
fi
# UnstakeRelayer
castArgs="$stOLASAddress unstakeRelayer()(address)"
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
if [ $result != $unstakeRelayerProxyAddress ]; then
  echo "${red}!!! UnstakeRelayer address is incorrect!${reset}"
  echo "${red}!!! Fetched address:$result${reset}"
  echo "${red}!!! Expected address:$unstakeRelayerProxyAddress${reset}"
  exit 0
fi
