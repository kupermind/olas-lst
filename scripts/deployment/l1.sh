# Deploy stOLAS
./scripts/deployment/deploy_l1_01_stolas.sh $1

# Deploy Lock
./scripts/deployment/deploy_l1_02_lock.sh $1

# Deploy LockProxy
./scripts/deployment/deploy_l1_03_lock_proxy.sh $1

# Deploy Distributor
./scripts/deployment/deploy_l1_04_distributor.sh $1

# Deploy DistributorProxy
./scripts/deployment/deploy_l1_05_distributor_proxy.sh $1

# Deploy UnstakeRelayer
./scripts/deployment/deploy_l1_06_unstake_relayer.sh $1

# Deploy UnstakeRelayerProxy
./scripts/deployment/deploy_l1_07_unstake_relayer_proxy.sh $1

# Deploy Depository
./scripts/deployment/deploy_l1_08_depository.sh $1

# Deploy DepositoryProxy
./scripts/deployment/deploy_l1_09_depository_proxy.sh $1

# Deploy Treasury
./scripts/deployment/deploy_l1_10_treasury.sh $1

# Deploy TreasuryProxy
./scripts/deployment/deploy_l1_11_treasury_proxy.sh $1

# Deploy GnosisDepositProcessorL1
./scripts/deployment/deploy_l1_12_gnosis_deposit_processor.sh $1

# Deploy BaseDepositProcessorL1
./scripts/deployment/deploy_l1_13_base_deposit_processor.sh $1

# Deploy LzOracle
./scripts/deployment/deploy_l1_14_lz_oracle.sh $1

# Change managers in stOLAS and Depository
./scripts/deployment/script_l1_01_change_managers.sh $1

# Change LzOracle address in Depository
./scripts/deployment/script_l1_02_change_lz_oracle.sh $1