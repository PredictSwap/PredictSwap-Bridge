# Invariant Map

> PredictSwap Bridge | 14 guards | 7 inferred | 3 not enforced on-chain

---

## 1. Enforced Guards (Reference)

Per-call preconditions. Heading IDs below (`G-N`) are anchor targets from x-ray.md attack surfaces.

#### G-1
`if (_amount == 0) revert ZeroAmount()` · `PredictionMarketEscrow.sol:175` · Prevents zero-value lock messages that would waste gas and pollute cross-chain accounting

#### G-2
`if (_polygonRecipient == address(0)) revert ZeroAddress()` · `PredictionMarketEscrow.sol:176` · Prevents minting wrapped tokens to the zero address on Polygon

#### G-3
`if (totalLocked[tokenId] < amount) revert InsufficientLockedBalance(...)` · `PredictionMarketEscrow.sol:223` · Prevents unlocking more tokens than are held in escrow — enforces solvency of the escrow per tokenId

#### G-4
`if (_to == address(0)) revert ZeroAddress()` · `WrappedPredictionToken.sol:107` · Prevents minting wrapped tokens to zero address

#### G-5
`if (_amount == 0) revert ZeroAmount()` · `WrappedPredictionToken.sol:108` · Prevents zero-amount mints that would increment totalSupply without creating tokens

#### G-6
`if (_amount == 0) revert ZeroAmount()` · `WrappedPredictionToken.sol:124` · Prevents zero-amount burns

#### G-7
`if (_token == predictionMarketContract && totalLocked[_tokenId] > 0) revert CannotRescueLockedTokens(...)` · `PredictionMarketEscrow.sol:248` · Prevents owner from rescuing prediction market tokens that back user bridge positions

#### G-8
`if (_amount == 0) revert ZeroAmount()` · `BridgeReceiver.sol:214` · Prevents zero-value bridge-back messages

#### G-9
`if (_bscRecipient == address(0)) revert ZeroAddress()` · `BridgeReceiver.sol:215` · Prevents sending unlock messages to zero address on BSC

#### G-10
`if (totalBridged[_tokenId] < _amount) revert InsufficientBridgedBalance(...)` · `BridgeReceiver.sol:216` · Prevents bridge-back exceeding the total minted wrapped supply — system-level solvency guard

#### G-11
`if (_bridge == address(0)) revert ZeroAddress()` · `WrappedPredictionToken.sol:87` · Prevents setting bridge to zero address (which would permanently lock mint/burn behind unreachable modifier)

#### G-12
`if (bridge != address(0)) revert BridgeAlreadySet()` · `WrappedPredictionToken.sol:88` · Prevents re-setting bridge address — enforces one-shot latch

#### G-13
`if (msg.sender != bridge) revert OnlyBridge()` · `WrappedPredictionToken.sol:65` · Restricts mint/burn to the authorized BridgeReceiver contract

#### G-14
`if (_token == address(wrappedToken) && totalBridged[_tokenId] > 0) revert CannotRescueLockedTokens(...)` · `BridgeReceiver.sol:261` · Prevents owner from rescuing wrapped tokens that represent user bridge positions

---

## 2. Inferred Invariants (Single-Contract)

#### I-1

`Conservation` · On-chain: **Yes**

> `totalBridged[tokenId] == WrappedPredictionToken.totalSupply(tokenId)` at all times

**Derivation** — NatSpec: `BridgeReceiver.sol:38` — *"totalBridged[tokenId] == WrappedPredictionToken.totalSupply(tokenId) at all times."* Confirmed by Δ-pair: `BridgeReceiver._lzReceive:187` does `Δ(totalBridged) = +amount` then `mint()` does `Δ(totalSupply) = +amount`; `BridgeReceiver.bridgeBack:218` does `Δ(totalBridged) = -amount` then `burn()` does `Δ(totalSupply) = -amount`. Both variables are written only through these two paths.

**If violated** — Wrapped tokens exist without backing on BSC, or locked tokens have no wrapped representation — bridge insolvency.

---

#### I-2

`Conservation` · On-chain: **Yes**

> `totalSupply[tokenId] == Σ balanceOf[addr][tokenId]` for all addresses

**Derivation** — Δ-pair: `WrappedPredictionToken.mint:109` does `Δ(totalSupply) = +amount` paired with OZ `_mint` doing `Δ(balanceOf[to]) = +amount`; `burn:125` does `Δ(totalSupply) = -amount` paired with `_burn` doing `Δ(balanceOf[from]) = -amount`. No other write sites for `totalSupply`.

**If violated** — totalSupply diverges from actual token distribution — accounting error for integrating protocols.

---

#### I-3

`Bound` · On-chain: **No**

> `_lzReceive` should be pausable during security incidents to halt all operations

**Derivation** — Guard-lift: `lock()` and `bridgeBack()` enforce `whenNotPaused` at `PredictionMarketEscrow.sol:174` and `BridgeReceiver.sol:213`. However, `_lzReceive` on both contracts (`PredictionMarketEscrow.sol:213`, `BridgeReceiver.sol:177`) writes to `totalLocked`/`totalBridged` WITHOUT `whenNotPaused`. This is documented as intentional ("in-flight messages must always land") but creates an unguarded write path for the state variables during pause.

**If violated** — During a security incident, attacker can continue minting/unlocking via in-flight or new LZ messages while protocol is paused.

---

#### I-4

`StateMachine` · On-chain: **Yes**

> `WrappedPredictionToken.bridge` transitions: `address(0) → concrete` with no reverse path

**Derivation** — Edge: `WrappedPredictionToken.sol:88` requires `bridge == address(0)` then `sol:89` sets `bridge = _bridge`. No function resets `bridge` back to `address(0)`. One-shot latch.

**If violated** — Bridge address could be changed, allowing unauthorized mint/burn.

---

#### I-5

`Bound` · On-chain: **Yes**

> `totalLocked[tokenId] >= 0` is always maintained (underflow prevented)

**Derivation** — Guard-lift: `PredictionMarketEscrow.sol:223` checks `totalLocked[tokenId] >= amount` before `sol:225` does `totalLocked[tokenId] -= amount`. Write sites: `lock:178` (increment only), `_lzReceive:225` (decrement with guard). Solidity 0.8 overflow protection on the increment. All write sites guarded.

**If violated** — Underflow would allow unlocking more than was locked — escrow drain.

---

## 3. Inferred Invariants (Cross-Contract)

#### X-1

On-chain: **No**

> BridgeReceiver assumes `_bscRecipient` can receive ERC-1155 tokens via `safeTransferFrom` on BSC

**Caller side** — `BridgeReceiver.sol:221` — encodes `_bscRecipient` (user-controlled) into LZ message payload without checking whether the address can receive ERC-1155

**Callee side** — `PredictionMarketEscrow.sol:226` — calls `IERC1155.safeTransferFrom(escrow, bscRecipient, ...)` which triggers `onERC1155Received` callback; if `bscRecipient` is a contract without the callback, the entire `_lzReceive` permanently reverts

**If violated** — Wrapped tokens already burned on Polygon but original tokens permanently stuck in escrow on BSC — irrecoverable fund loss.

---

#### X-2

On-chain: **No**

> Cross-chain message delivery is guaranteed by LayerZero — state is committed on source before delivery confirmation on destination

**Caller side** — `PredictionMarketEscrow.sol:178-182` — `totalLocked += amount` and token transfer happen before `_lzSend`; `BridgeReceiver.sol:218-222` — `totalBridged -= amount` and burn happen before `_lzSend`

**Callee side** — `BridgeReceiver._lzReceive:187` / `PredictionMarketEscrow._lzReceive:225` — destination execution is deferred and may permanently fail

**If violated** — Tokens locked/burned on source chain but never minted/unlocked on destination — permanent fund loss depending on LayerZero retry success.

---

## 4. Economic Invariants

#### E-1

On-chain: **Yes** (within single chain)

> Total wrapped token supply on Polygon is always backed 1:1 by locked tokens on BSC

**Follows from** — `I-1` (totalBridged == totalSupply) + `X-2` (cross-chain delivery assumption). Within Polygon: `totalBridged` tracks exactly what was minted. Cross-chain: requires all LZ messages to deliver successfully.

**If violated** — Unbacked wrapped tokens circulate on Polygon — bridge insolvency if users try to bridge back more than is locked.

---

#### E-2

On-chain: **No**

> `IERC1155(predictionMarketContract).balanceOf(escrow, tokenId) >= totalLocked[tokenId]` for all tokenIds

**Follows from** — `I-5` (totalLocked underflow protected) + `X-2` (delivery assumption). The escrow's actual ERC-1155 balance should always be >= totalLocked. However, if the prediction market ERC-1155 has fee-on-transfer behavior, the actual balance could be less than totalLocked — no post-transfer balance check exists at `PredictionMarketEscrow.sol:179`.

**If violated** — Escrow becomes insolvent — unlock messages would fail because escrow doesn't hold enough tokens.
