# PredictSwap Bridge

Cross-chain bridge for locking ERC-1155 prediction market shares on BSC and minting wrapped equivalents on Polygon for use in SwapPool.

## Architecture

```
BSC (BNB Smart Chain)                    Polygon
┌───────────────────┐                   ┌─────────────────────┐
│      Escrow       │◄─── LayerZero ───►│  BridgeReceiver     │
│  (lock/unlock)    │      V2 OApp      │  (mint/burn)        │
└───────────────────┘                   ├─────────────────────┤
                                        │ WrappedOpinionToken │
                                        │  (ERC-1155)         │
                                        └─────────────────────┘
```

**Flow: BSC → Polygon (lock & mint)**
1. User transfers ERC-1155 shares to `OpinionEscrow` on BSC
2. Escrow sends LayerZero message to `BridgeReceiver` on Polygon
3. BridgeReceiver mints `WrappedOpinionToken` to user's Polygon address

**Flow: Polygon → BSC (burn & unlock)**
1. User calls `bridgeBack()` on `BridgeReceiver`, burning wrapped tokens
2. BridgeReceiver sends LayerZero message to `OpinionEscrow` on BSC
3. Escrow releases original shares to user's BSC address

## Contracts

| Contract | Chain | Description |
|---|---|---|
| `OpinionEscrow` | BSC | LayerZero OApp. Locks/unlocks ERC-1155 shares. |
| `BridgeReceiver` | Polygon | LayerZero OApp. Mints/burns wrapped tokens. |
| `WrappedOpinionToken` | Polygon | ERC-1155 wrapped representation, 1:1 backed by locked shares on BSC. |

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
forge build
forge test -vvv
forge test --match-contract BridgeIntegration -vvvv
forge test --gas-report
```

## Deployment

All deploy scripts require environment variables:

```bash
source .env
```

### 1. Deploy mock ERC-1155 (testnet only)

```bash
forge script script/integration_tests/DeployMockOpinion.s.sol:DeployMockOpinion \
  --rpc-url $BSC_RPC_URL \
  --broadcast \
  --verify \
  --verifier etherscan \
  --verifier-url "https://api.etherscan.io/v2/api?chainid=$BSC_CHAIN_ID" \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Add `OPINION_CONTRACT` to `.env`.

```bash
forge script script/integration_tests/MintMock.s.sol \
  --rpc-url $BSC_RPC_URL \
  --broadcast
```

Faucets: [BSC testnet](https://www.bnbchain.org/en/testnet-faucet) · [Polygon Amoy](https://faucet.stakepool.dev.br/amoy)

### 2. Deploy BSC contracts

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

Add `OPINION_ESCROW_ADDRESS` to `.env`.

### 3. Deploy Polygon contracts

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

Add `BRIDGE_RECEIVER_ADDRESS` and `WRAPPED_OPINION_TOKEN_ADDRESS` to `.env`.

### 4. Configure DVN

```bash
forge script script/integration_tests/SetConfig.s.sol:SetConfig --sig "SetLibrariesBSC()" \
  --rpc-url $BSC_RPC_URL \
  --broadcast

forge script script/integration_tests/SetConfig.s.sol:SetConfig --sig "SetLibrariesPolygon()" \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast
```

### 5. Set peers

```bash
forge script script/SetPeers.s.sol:SetPeerBSC \
  --rpc-url $BSC_RPC_URL \
  --broadcast

forge script script/SetPeers.s.sol:SetPeerPolygon \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast
```

### 6. Set destination gas limits

```bash
forge script script/SetDstGasLimit.s.sol:SetDstGasLimitBSC \
  --rpc-url $BSC_RPC_URL \
  --broadcast

forge script script/SetDstGasLimit.s.sol:SetDstGasLimitPolygon \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast
```

### 7. Unpause contracts

```bash
forge script script/UnpauseContracts.s.sol:UnpauseBSC \
  --rpc-url $BSC_RPC_URL \
  --broadcast

forge script script/UnpauseContracts.s.sol:UnpausePolygon \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast
```

## Usage

### Bridge tokens (BSC → Polygon)

```bash
forge script script/integration_tests/BridgeTokens.s.sol \
  --rpc-url $BSC_RPC_URL \
  --broadcast
```

### Bridge back (Polygon → BSC)

```bash
forge script script/integration_tests/BridgeBack.s.sol \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast
```

### Inspect LayerZero config

```bash
forge script script/integration_tests/GetConfig.s.sol:GetConfigScript --sig "getPolygonReceive()" --rpc-url $POLYGON_RPC_URL
forge script script/integration_tests/GetConfig.s.sol:GetConfigScript --sig "getPolygonSend()"    --rpc-url $POLYGON_RPC_URL
forge script script/integration_tests/GetConfig.s.sol:GetConfigScript --sig "getBSCReceive()"    --rpc-url $BSC_RPC_URL
forge script script/integration_tests/GetConfig.s.sol:GetConfigScript --sig "getBSCSend()"       --rpc-url $BSC_RPC_URL
```

## Key Design Decisions

- **Wrapped tokens, not bridged originals** — `WrappedOpinionToken` is minted on Polygon rather than bridging the original ERC-1155. No permissions needed from the source platform.
- **Message-only bridging** — Native tokens never leave their home chain. LayerZero carries messages only; value is locked on BSC and represented 1:1 on Polygon.
- **`setBridge` must be called before ownership transfer** — `WrappedOpinionToken` requires the bridge address to be set while the deployer still owns it. This is a one-time, irreversible operation (`BridgeAlreadySet` guard).

## License

MIT