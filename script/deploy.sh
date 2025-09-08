#!/bin/bash

# Block Time Anomaly Trap - Deployment Script
# Automates the complete deployment process for Hoodi Testnet

set -e  # Exit on any error

echo "Starting Block Time Anomaly Trap Deployment..."
echo "=================================================="

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v forge &> /dev/null; then
    echo "Foundry not found. Please install: curl -L https://foundry.paradigm.xyz | bash"
    exit 1
fi

if ! command -v drosera &> /dev/null; then
    echo "Drosera CLI not found. Please install: curl -L https://install.drosera.io | bash"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "PRIVATE_KEY environment variable not set"
    echo "   Export your private key: export PRIVATE_KEY=0x..."
    exit 1
fi

if [ -z "$DROSERA_PRIVATE_KEY" ]; then
    echo "DROSERA_PRIVATE_KEY not set, using PRIVATE_KEY"
    export DROSERA_PRIVATE_KEY=$PRIVATE_KEY
fi

echo "All prerequisites found"

# Compile contracts
echo "Compiling contracts..."
forge build

if [ $? -ne 0 ]; then
    echo "Compilation failed"
    exit 1
fi

echo "Contracts compiled successfully"

# Deploy contracts using Foundry script
echo "Deploying contracts to Hoodi Testnet..."
forge script script/Deploy.s.sol --rpc-url https://ethereum-hoodi-rpc.publicnode.com --broadcast --verify

if [ $? -ne 0 ]; then
    echo "Contract deployment failed"
    exit 1
fi

echo "Contracts deployed successfully"

# Extract addresses from broadcast files
RESPONSE_ADDRESS=$(jq -r '.receipts[] | select(.contractName == "BlockAnomalyResponse") | .contractAddress' broadcast/Deploy.s.sol/560048/run-latest.json)
TRAP_ADDRESS=$(jq -r '.receipts[] | select(.contractName == "BlockTimeAnomalyTrap") | .contractAddress' broadcast/Deploy.s.sol/560048/run-latest.json)

echo "Deployed Addresses:"
echo "   Response Contract: $RESPONSE_ADDRESS"
echo "   Trap Contract: $TRAP_ADDRESS"

# Update drosera.toml with response address
echo "Updating drosera.toml..."
sed -i "s/0xYourBlockAnomalyResponseAddress/$RESPONSE_ADDRESS/g" drosera.toml

# Deploy to Drosera Network
echo "Deploying trap to Drosera Network..."
drosera apply

if [ $? -ne 0 ]; then
    echo "Drosera deployment failed"
    exit 1
fi

# Save deployment info
echo "Saving deployment information..."
cat > deployment/addresses.json << EOF
{
  "network": "Hoodi Testnet",
  "chainId": 560048,
  "deploymentDate": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "contracts": {
    "BlockAnomalyResponse": "$RESPONSE_ADDRESS",
    "BlockTimeAnomalyTrap": "$TRAP_ADDRESS"
  },
  "links": {
    "responseContract": "https://hoodi.etherscan.io/address/$RESPONSE_ADDRESS",
    "trapContract": "https://hoodi.etherscan.io/address/$TRAP_ADDRESS"
  }
}
EOF

echo "Deployment complete!"
echo ""
echo "SUCCESS! Your Block Time Anomaly Trap is deployed:"
echo "   Response Contract: https://hoodi.etherscan.io/address/$RESPONSE_ADDRESS"
echo "   Trap Contract: https://hoodi.etherscan.io/address/$TRAP_ADDRESS"
echo ""
echo "Next Steps:"
echo "   1. Update README.md with these addresses"
echo "   2. Test the trap: drosera dryrun"
echo "   3. Hydrate with DRO: drosera hydrate --trap-address $TRAP_ADDRESS --dro-amount 10"
