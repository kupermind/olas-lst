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

# Get network name from network_mainnet or network_sepolia or another testnet
networkL2=${2%_*}

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

# L1 addresses
olasAddressL1=$(jq -r ".olasAddress" $globalsL1)
veOLASAddress=$(jq -r ".veOLASAddress" $globalsL1)
stOLASAddress=$(jq -r ".stOLASAddress" $globalsL1)
lockProxyAddress=$(jq -r ".lockProxyAddress" $globalsL1)
distributorProxyAddress=$(jq -r ".distributorProxyAddress" $globalsL1)
unstakeRelayerProxyAddress=$(jq -r ".unstakeRelayerProxyAddress" $globalsL1)
depositoryProxyAddress=$(jq -r ".depositoryProxyAddress" $globalsL1)
treasuryProxyAddress=$(jq -r ".treasuryProxyAddress" $globalsL1)
lzOracleAddress=$(jq -r ".lzOracleAddress" $globalsL1)
olasGovernorAddress=$(jq -r ".olasGovernorAddress" $globalsL1)
depositProcessorL1Address=$(jq -r ".${networkL2}DepositProcessorL1Address" $globalsL1)

# L2 addresses
olasAddressL2=$(jq -r ".olasAddress" $globalsL2)
collectorProxyAddress=$(jq -r ".collectorProxyAddress" $globalsL2)
stakingManagerProxyAddress=$(jq -r ".stakingManagerProxyAddress" $globalsL2)
stakingProcessorL2Address=$(jq -r ".${networkL2}StakingProcessorL2Address" $globalsL2)

addressZero=$(cast address-zero)
castCallHeader="cast call --rpc-url $networkURLL1$API_KEY"

echo "${green}Checking stOLAS${reset}"
# Depository
castArgs="$stOLASAddress depository()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $depositoryProxyAddress ]; then
  echo "${red}!!! Depository address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $depositoryProxyAddress${reset}"
fi
# Treasury
castArgs="$stOLASAddress treasury()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $treasuryProxyAddress ]; then
  echo "${red}!!! Treasury address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $treasuryProxyAddress${reset}"
fi
# Distributor
castArgs="$stOLASAddress distributor()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $distributorProxyAddress ]; then
  echo "${red}!!! Distributor address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $distributorProxyAddress${reset}"
fi
# UnstakeRelayer
castArgs="$stOLASAddress unstakeRelayer()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $unstakeRelayerProxyAddress ]; then
  echo "${red}!!! UnstakeRelayer address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $unstakeRelayerProxyAddress${reset}"
fi


# L1
echo "${green}Checking Depository${reset}"
# OLAS
castArgs="$depositoryProxyAddress olas()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $olasAddressL1 ]; then
  echo "${red}!!! OLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $olasAddressL1${reset}"
fi
# Treasury
castArgs="$depositoryProxyAddress treasury()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $treasuryProxyAddress ]; then
  echo "${red}!!! Treasury address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $treasuryProxyAddress${reset}"
fi
# stOLAS
castArgs="$depositoryProxyAddress st()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $stOLASAddress ]; then
  echo "${red}!!! stOLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $stOLASAddress${reset}"
fi
# LzOracle
castArgs="$depositoryProxyAddress lzOracle()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $lzOracleAddress ]; then
  echo "${red}!!! LzOracle address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $lzOracleAddress${reset}"
fi
# productType - alpha
castArgs="$depositoryProxyAddress productType()(uint8)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != 0 ]; then
  echo "${red}!!! Product type is incorrect!${reset}"
  echo "${red}!!! Fetched type:$result${reset}"
  echo "${red}!!! Expected type:0${reset}"
fi


echo "${green}Checking Treasury${reset}"
# OLAS
castArgs="$treasuryProxyAddress olas()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $olasAddressL1 ]; then
  echo "${red}!!! OLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $olasAddressL1${reset}"
fi
# Depository
castArgs="$treasuryProxyAddress depository()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $depositoryProxyAddress ]; then
  echo "${red}!!! Depository address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $depositoryProxyAddress${reset}"
fi
# stOLAS
castArgs="$treasuryProxyAddress st()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $stOLASAddress ]; then
  echo "${red}!!! stOLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $stOLASAddress${reset}"
fi
# withdrawDelay - needs to be more than 0
castArgs="$treasuryProxyAddress withdrawDelay()(uint256)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result == 0 ]; then
  echo "${red}!!! withdrawDelay is incorrect!${reset}"
  echo "${red}!!! Fetched: $result${reset}"
  echo "${red}!!! Expected: >0${reset}"
fi


echo "${green}Checking Lock${reset}"
# OLAS
castArgs="$lockProxyAddress olas()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $olasAddressL1 ]; then
  echo "${red}!!! OLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $olasAddressL1${reset}"
fi
# veOLAS
castArgs="$lockProxyAddress ve()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $veOLASAddress ]; then
  echo "${red}!!! veOLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $veOLASAddress${reset}"
fi
# olasGovernor
castArgs="$lockProxyAddress olasGovernor()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $olasGovernorAddress ]; then
  echo "${red}!!! olasGovernor address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $olasGovernorAddress${reset}"
fi


echo "${green}Checking Distributor${reset}"
# OLAS
castArgs="$distributorProxyAddress olas()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $olasAddressL1 ]; then
  echo "${red}!!! OLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $olasAddressL1${reset}"
fi
# stOLAS
castArgs="$distributorProxyAddress st()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $stOLASAddress ]; then
  echo "${red}!!! stOLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $stOLASAddress${reset}"
fi
# Lock
castArgs="$distributorProxyAddress lock()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $lockProxyAddress ]; then
  echo "${red}!!! lock address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $lockProxyAddress${reset}"
fi


echo "${green}Checking UnstakeRelayer${reset}"
# OLAS
castArgs="$unstakeRelayerProxyAddress olas()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $olasAddressL1 ]; then
  echo "${red}!!! OLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $olasAddressL1${reset}"
fi
# stOLAS
castArgs="$unstakeRelayerProxyAddress st()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $stOLASAddress ]; then
  echo "${red}!!! stOLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $stOLASAddress${reset}"
fi


echo "${green}Checking ${networkL2}DepositProcessorL1${reset}"
# OLAS
castArgs="$depositProcessorL1Address olas()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $olasAddressL1 ]; then
  echo "${red}!!! OLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $olasAddressL1${reset}"
fi
# Depository
castArgs="$depositProcessorL1Address l1Depository()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $depositoryProxyAddress ]; then
  echo "${red}!!! Depository address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $depositoryProxyAddress${reset}"
fi
# l2StakingProcessor
castArgs="$depositProcessorL1Address l2StakingProcessor()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $stakingProcessorL2Address ]; then
  echo "${red}!!! l2StakingProcessor address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $stakingProcessorL2Address${reset}"
fi
# owner
castArgs="$depositProcessorL1Address owner()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $addressZero ]; then
  echo "${red}!!! owner address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $addressZero${reset}"
fi


# L2
castCallHeader="cast call --rpc-url $networkURLL2"

echo "${green}Checking Collector${reset}"
# OLAS
castArgs="$collectorProxyAddress olas()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $olasAddressL2 ]; then
  echo "${red}!!! OLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $olasAddressL2${reset}"
fi
# StakingManager
castArgs="$collectorProxyAddress stakingManager()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $stakingManagerProxyAddress ]; then
  echo "${red}!!! StakingManager address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $stakingManagerProxyAddress${reset}"
fi
# l2StakingProcessor
castArgs="$collectorProxyAddress l2StakingProcessor()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $stakingProcessorL2Address ]; then
  echo "${red}!!! l2StakingProcessor address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $stakingProcessorL2Address${reset}"
fi
# protocolFactor
castArgs="$collectorProxyAddress protocolFactor()(uint256)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != 0 ]; then
  echo "${red}!!! protocolFactor is incorrect!${reset}"
  echo "${red}!!! Fetched: $result${reset}"
  echo "${red}!!! Expected: 0${reset}"
fi
# mapOperationReceiverBalances
#[$REWARD,$UNSTAKE,$UNSTAKE_RETIRED] => [$distributorProxyAddress,$treasuryProxyAddress,$unstakeRelayerProxyAddress]"
REWARD="0x0b9821ae606ebc7c79bf3390bdd3dc93e1b4a7cda27aad60646e7b88ff55b001"
castArgs="$collectorProxyAddress mapOperationReceiverBalances(bytes32)(uint256,address) $REWARD"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
resultAddress=$(echo "$result" | grep "0x")
if [ $resultAddress != $distributorProxyAddress ]; then
  echo "${red}!!! Distributor address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $distributorProxyAddress${reset}"
fi
UNSTAKE="0x8ca9a95e41b5eece253c93f5b31eed1253aed6b145d8a6e14d913fdf8e732293"
castArgs="$collectorProxyAddress mapOperationReceiverBalances(bytes32)(uint256,address) $UNSTAKE"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
resultAddress=$(echo "$result" | grep "0x")
if [ $resultAddress != $treasuryProxyAddress ]; then
  echo "${red}!!! Treasury address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $treasuryProxyAddress${reset}"
fi
UNSTAKE_RETIRED="0x9065ad15d9673159e4597c86084aff8052550cec93c5a6e44b3f1dba4c8731b3"
castArgs="$collectorProxyAddress mapOperationReceiverBalances(bytes32)(uint256,address) $UNSTAKE_RETIRED"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
resultAddress=$(echo "$result" | grep "0x")
if [ $resultAddress != $unstakeRelayerProxyAddress ]; then
  echo "${red}!!! UnstakeRelayer address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $unstakeRelayerProxyAddress${reset}"
fi


echo "${green}Checking StakingManager${reset}"
# OLAS
castArgs="$stakingManagerProxyAddress olas()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $olasAddressL2 ]; then
  echo "${red}!!! OLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $olasAddressL2${reset}"
fi
# l2StakingProcessor
castArgs="$stakingManagerProxyAddress l2StakingProcessor()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $stakingProcessorL2Address ]; then
  echo "${red}!!! l2StakingProcessor address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $stakingProcessorL2Address${reset}"
fi
# Collector
castArgs="$stakingManagerProxyAddress collector()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $collectorProxyAddress ]; then
  echo "${red}!!! Collector address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $collectorProxyAddress${reset}"
fi
# Balance in wei
castCmd="cast call --rpc-url $networkURLL2 $stakingManagerProxyAddress"
result=$($castCmd)
if [ $result == 0 ]; then
  echo "${red}!!! Balance is incorrect!${reset}"
  echo "${red}!!! Fetched: $result${reset}"
  echo "${red}!!! Expected: > 0${reset}"
fi


echo "${green}Checking ${networkL2}StakingProcessorL2${reset}"
# OLAS
castArgs="$stakingProcessorL2Address olas()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $olasAddressL2 ]; then
  echo "${red}!!! OLAS address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $olasAddressL2${reset}"
fi
# StakingManager
castArgs="$stakingProcessorL2Address stakingManager()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $stakingManagerProxyAddress ]; then
  echo "${red}!!! StakingManager address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $stakingManagerProxyAddress${reset}"
fi
# Collector
castArgs="$stakingProcessorL2Address collector()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $collectorProxyAddress ]; then
  echo "${red}!!! Collector address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $collectorProxyAddress${reset}"
fi
# l1DepositProcessor
castArgs="$stakingProcessorL2Address l1DepositProcessor()(address)"
castCmd="$castCallHeader $castArgs"
result=$($castCmd)
if [ $result != $depositProcessorL1Address ]; then
  echo "${red}!!! l1DepositProcessor address is incorrect!${reset}"
  echo "${red}!!! Fetched address: $result${reset}"
  echo "${red}!!! Expected address: $depositProcessorL1Address${reset}"
fi
# owner (after setting to DAO address)
#castArgs="$stakingProcessorL2Address owner()(address)"
#castCmd="$castCallHeader $castArgs"
#result=$($castCmd)
#if [ $result != $bridgeMediator ]; then
#  echo "${red}!!! owner address is incorrect!${reset}"
#  echo "${red}!!! Fetched address: $result${reset}"
#  echo "${red}!!! Expected address: $bridgeMediator${reset}"
#fi
