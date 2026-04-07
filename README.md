# PredictSwap Bridge Contracts

Cross-chain bridge for Opinion ERC-1155 prediction market tokens between BSC and Polygon.

## Architecture

```
BSC (BNB Smart Chain)                    Polygon
┌───────────────────┐                   ┌────────────────────┐
│  OpinionEscrow    │◄── LayerZero ───►│  BridgeReceiver     │
│  (lock/unlock)    │    v2 OApp       │  (mint/burn)        │
└───────────────────┘                   ├────────────────────┤
                                        │ WrappedOpinionToken │
                                        │  (ERC-1155)         │
                                        ├────────────────────┤
                                        │  AddressRegistry    │
                                        │  (EOA → Safe map)   │
                                        └────────────────────┘
```

**Flow: BSC → Polygon (lock & mint)**
1. User transfers Opinion ERC-1155 shares to `OpinionEscrow` on BSC
2. Escrow sends LayerZero message to `BridgeReceiver` on Polygon
3. BridgeReceiver mints `WrappedOpinionToken` to user's Polygon address

**Flow: Polygon → BSC (burn & unlock)**
1. User calls `bridgeBack()` on `BridgeReceiver`, burning wrapped tokens
2. BridgeReceiver sends LayerZero message to `OpinionEscrow` on BSC
3. Escrow releases original Opinion shares to user's BSC Safe address

## Setup

```bash
# Install Foundry (if not installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install foundry-rs/forge-std
forge install layerzero-labs/devtools
forge install layerzero-labs/LayerZero-v2
forge install OpenZeppelin/openzeppelin-contracts
git submodule add https://github.com/GNSPS/solidity-bytes-utils.git lib/solidity-bytes-utils
```

## Build & Test

```bash
# Compile
forge build

# Run all tests
forge test -vvv

# Run integration tests with full trace
forge test --match-contract BridgeIntegration -vvvv

# Gas report
forge test --gas-report
```

## Contracts

| Contract | Chain | Description |
|----------|-------|-------------|
| `OpinionEscrow` | BSC | LayerZero OApp. Locks/unlocks Opinion ERC-1155 shares. |
| `BridgeReceiver` | Polygon | LayerZero OApp. Mints/burns wrapped tokens. |
| `WrappedOpinionToken` | Polygon | ERC-1155 wrapped representation of Opinion shares. |

## Deployment

### 1. Deploy BSC (Optional for Testing)

source .env

### 2. Deploy and mint Dummy Opinion ERC-1155 (Optional for Testing)

```bash
forge script script/integration_tests/DeployMockOpinion.s.sol:DeployMockOpinion \
  --rpc-url $BSC_RPC_URL \
  --broadcast \
  --verify \
  --verifier etherscan \
  --verifier-url "https://api.etherscan.io/v2/api?chainid=$BSC_CHAIN_ID" \
  --etherscan-api-key $ETHERSCAN_API_KEY

add OPINION_CONTRACT into .env

forge script script/integration_tests/MintMock.s.sol \
  --rpc-url $BSC_RPC_URL \
  --broadcast
```


### 3. Deploy BSC Contracts

faucet - https://www.bnbchain.org/en/testnet-faucet

```bash
forge script script/DeployBSC.s.sol:DeployBSC \
  --rpc-url $BSC_RPC_URL \
  --broadcast \
  --verify \
  --verifier etherscan \
  --verifier-url "https://api.etherscan.io/v2/api?chainid=$BSC_CHAIN_ID" \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv
```

add OPINION_ESCROW_ADDRESS into .env

### 4. Deploy Polygon Contracts

faucet - https://faucet.stakepool.dev.br/amoy

```bash
forge script script/DeployPolygon.s.sol:DeployPolygon \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast \
  --verify \
  --verifier etherscan \
  --verifier-url "https://api.etherscan.io/v2/api?chainid=$POLYGON_CHAIN_ID" \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv
```

add BRIDGE_RECEIVER_ADDRESS and WRAPPED_OPINION_TOKEN_ADDRESS into .env

### 5. Config DVN
```bash
# Set peer on BSC
forge script script/integration_tests/SetConfig.s.sol:SetConfig --sig "SetLibrariesBSC()" \
--rpc-url $BSC_RPC_URL \
--broadcast

# Set peer on Polygon
forge script script/integration_tests/SetConfig.s.sol:SetConfig --sig "SetLibrariesPolygon()" \
--rpc-url $POLYGON_RPC_URL \
--broadcast
```

### 6. Set Peers

```bash
# Set peer on BSC
forge script script/SetPeers.s.sol:SetPeerBSC \
  --rpc-url $BSC_RPC_URL \
  --broadcast

# Set peer on Polygon
forge script script/SetPeers.s.sol:SetPeerPolygon \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast
```

### 7. Set DstGas

```bash
# Set peer on BSC
forge script script/SetDstGasLimit.s.sol:SetDstGasLimitBSC \
  --rpc-url $BSC_RPC_URL \
  --broadcast

# Set peer on Polygon
forge script script/SetDstGasLimit.s.sol:SetDstGasLimitPolygon \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast
```

### 8. Unpause contracts

```bash
# Set peer on BSC
forge script script/UnpauseContracts.s..sol:UnpauseBSC \
  --rpc-url $BSC_RPC_URL \
  --broadcast

# Set peer on Polygon
forge script script/UnpauseContracts.s.sol:UnpausePolygon \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast
```

### Usage

# Bridge Tokens

```bash
forge script script/integration_tests/BridgeTokens.s.sol \
  --rpc-url $BSC_RPC_URL \
  --broadcast
```

# Bridge Back

```bash
forge script script/integration_tests/BridgeBack.s.sol \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast
```

# Get Config

```bash
forge script script/integration_tests/GetConfig.s.sol:GetConfigScript --sig "getPolygonReceive()" --rpc-url $POLYGON_RPC_URL
forge script script/integration_tests/GetConfig.s.sol:GetConfigScript --sig "getPolygonSend()" --rpc-url $POLYGON_RPC_URL
forge script script/integration_tests/GetConfig.s.sol:GetConfigScript --sig "getBSCReceive()" --rpc-url $BSC_RPC_URL
forge script script/integration_tests/GetConfig.s.sol:GetConfigScript --sig "getBSCSend()" --rpc-url $BSC_RPC_URL
```


## Key Design Decisions

- **Wrapped tokens, not bridged originals**: We mint our own ERC-1155 on Polygon rather than bridging Opinion's tokens. No platform permissions needed.


## License

MIT
