# Entry Point Map

> Prediction Market NFT Bridge | 22 entry points | 3 permissionless | 2 role-gated | 17 admin-only

---

## Protocol Flow Paths

### Setup (Owner -- per escrow contract)

`deploy()` -> `setPeer(dstEid, peerAddress)` -> `setDstGasLimit(gasLimit)` -> `unpause()`

### Setup (Owner -- WrappedPredictionToken)

`deploy()` -> `setBridge(bridgeReceiverAddress)`  <-- one-time, irreversible

### User Flow (Bridge In)

`[owner setup above]` -> `OpinionEscrow.lock()` -> LZ message -> `BridgeReceiver._lzReceive()`
                                                                       └-> `WrappedPredictionToken.mint()`

### User Flow (Bridge Back)

`[bridge in above]` -> `BridgeReceiver.bridgeBack()`  <-- user must hold wrapped token balance
                            ├-> `WrappedPredictionToken.burn()`
                            └-> LZ message -> `OpinionEscrow._lzReceive()`
                                                  └-> `IERC1155.safeTransferFrom(escrow -> user)`

### Emergency (Owner)

`pause()` -> `rescueTokens()` / `rescueERC20()` / `rescueETH()`  <-- only for non-locked assets

---

## Permissionless

### `OpinionEscrow.lock()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, whenNotPaused, nonReentrant |
| Caller | User (prediction market share holder on BSC) |
| Parameters | _tokenId (user-controlled), _amount (user-controlled), _polygonRecipient (user-controlled), _options (user-controlled) |
| Call chain | -> IERC1155(opinionContract).safeTransferFrom(msg.sender, escrow) -> _lzSend(polygonEid, payload) |
| State modified | totalLocked[_tokenId] += _amount |
| Value flow | Tokens: user -> OpinionEscrow (ERC-1155 locked); msg.value: user -> LZ endpoint (messaging fee) |
| Reentrancy guard | yes |

### `PredictFunEscrow.lock()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, whenNotPaused, nonReentrant |
| Caller | User (PredictFun share holder on BSC) |
| Parameters | _tokenId (user-controlled), _amount (user-controlled), _polygonRecipient (user-controlled), _options (user-controlled) |
| Call chain | -> IERC1155(predictFunContract).safeTransferFrom(msg.sender, escrow) -> _lzSend(polygonEid, payload) |
| State modified | totalLocked[_tokenId] += _amount |
| Value flow | Tokens: user -> PredictFunEscrow (ERC-1155 locked); msg.value: user -> LZ endpoint (messaging fee) |
| Reentrancy guard | yes |

### `BridgeReceiver.bridgeBack()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, whenNotPaused, nonReentrant |
| Caller | User (wrapped token holder on Polygon) |
| Parameters | _tokenId (user-controlled), _amount (user-controlled), _bscRecipient (user-controlled), _options (user-controlled) |
| Call chain | -> WrappedPredictionToken.burn(msg.sender, _tokenId, _amount) -> _lzSend(bscEid, payload) |
| State modified | totalBridged[_tokenId] -= _amount |
| Value flow | Tokens: WrappedPredictionToken burned from user; msg.value: user -> LZ endpoint (messaging fee) |
| Reentrancy guard | yes |

---

## Role-Gated

### `onlyBridge` (BridgeReceiver contract)

#### `WrappedPredictionToken.mint()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, onlyBridge |
| Caller | BridgeReceiver (via _lzReceive on bridge-in) |
| Parameters | _to (protocol-derived from LZ message), _tokenId (protocol-derived), _amount (protocol-derived) |
| Call chain | -> ERC1155._mint(_to, _tokenId, _amount, "") |
| State modified | totalSupply[_tokenId] += _amount, balanceOf[_to][_tokenId] += _amount |
| Value flow | Tokens: minted to _to |
| Reentrancy guard | no (caller _lzReceive has nonReentrant) |

#### `WrappedPredictionToken.burn()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, onlyBridge |
| Caller | BridgeReceiver (via bridgeBack) |
| Parameters | _from (protocol-derived -- always msg.sender of bridgeBack), _tokenId (user-controlled), _amount (user-controlled) |
| Call chain | -> ERC1155._burn(_from, _tokenId, _amount) |
| State modified | totalSupply[_tokenId] -= _amount, balanceOf[_from][_tokenId] -= _amount |
| Value flow | Tokens: burned from _from |
| Reentrancy guard | no (caller bridgeBack has nonReentrant) |

---

## Admin-Only

### OpinionEscrow (onlyOwner)

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| OpinionEscrow | `pause()` | none | _paused = true |
| OpinionEscrow | `unpause()` | none | _paused = false |
| OpinionEscrow | `setDstGasLimit(uint128)` | _gasLimit (owner-provided) | dstGasLimit, enforcedOptions[polygonEid][SEND] |
| OpinionEscrow | `rescueTokens(address,uint256,uint256,address)` | _token, _tokenId, _amount, _to | none (external transfer) |
| OpinionEscrow | `rescueERC20(address,uint256,address)` | _token, _amount, _to | none (external transfer) |
| OpinionEscrow | `rescueETH(address payable)` | _to | none (ETH transfer) |

### PredictFunEscrow (onlyOwner)

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| PredictFunEscrow | `pause()` | none | _paused = true |
| PredictFunEscrow | `unpause()` | none | _paused = false |
| PredictFunEscrow | `setDstGasLimit(uint128)` | _gasLimit (owner-provided) | dstGasLimit, enforcedOptions[polygonEid][SEND] |
| PredictFunEscrow | `rescueTokens(address,uint256,uint256,address)` | _token, _tokenId, _amount, _to | none (external transfer) |
| PredictFunEscrow | `rescueERC20(address,uint256,address)` | _token, _amount, _to | none (external transfer) |
| PredictFunEscrow | `rescueETH(address payable)` | _to | none (ETH transfer) |

### BridgeReceiver (onlyOwner)

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| BridgeReceiver | `pause()` | none | _paused = true |
| BridgeReceiver | `unpause()` | none | _paused = false |
| BridgeReceiver | `setDstGasLimit(uint128)` | _gasLimit (owner-provided) | dstGasLimit, enforcedOptions[bscEid][SEND] |
| BridgeReceiver | `rescueTokens(address,uint256,uint256,address)` | _token, _tokenId, _amount, _to | none (external transfer) |
| BridgeReceiver | `rescueERC20(address,uint256,address)` | _token, _amount, _to | none (external transfer) |
| BridgeReceiver | `rescueETH(address payable)` | _to | none (ETH transfer) |

### WrappedPredictionToken (onlyOwner)

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| WrappedPredictionToken | `setBridge(address)` | _bridge | bridge = _bridge (one-time, irreversible) |

### Inherited from OApp (onlyOwner, all contracts except WrappedPredictionToken)

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| All OApp contracts | `setPeer(uint32,bytes32)` | _eid, _peer | peers[_eid] = _peer |
