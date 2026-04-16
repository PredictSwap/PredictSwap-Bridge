# X-Ray Report

> Prediction Market NFT Bridge | 430 nSLOC | 44cea07 (`main`) | Foundry | 16/04/26

---

## 1. Protocol Overview

**What it does:** Bridges ERC-1155 prediction market shares from BSC to Polygon via LayerZero, issuing 1:1 wrapped representations on the destination chain.

- **Users**: Prediction market participants who want to use their BSC-based ERC-1155 shares on Polygon
- **Core flow**: Lock ERC-1155 shares in escrow on BSC -> LayerZero message -> mint wrapped ERC-1155 on Polygon (and reverse)
- **Key mechanism**: Lock-and-mint bridge pattern with LayerZero V2 OApp messaging
- **Token model**: Two wrapped ERC-1155 token contracts on Polygon (WrappedPredictionToken), 1:1 backed by locked shares in BSC escrows
- **Admin model**: Single `owner` (Ownable) per contract, no timelock, no multisig enforced in code

For a visual overview of the protocol's architecture, see the [architecture diagram](architecture.svg).

### Contracts in Scope

| Subsystem | Key Contracts | nSLOC | Role |
|-----------|--------------|------:|------|
| BSC Escrow | OpinionEscrow, PredictFunEscrow | 264 | Lock ERC-1155 shares on BSC, send/receive LZ messages |
| Polygon Bridge | BridgeReceiver | 124 | Receive LZ messages, mint/burn wrapped tokens, initiate bridge-back |
| Wrapped Token | WrappedPredictionToken | 42 | ERC-1155 wrapped representation of locked BSC shares |

### How It Fits Together

The core trick: lock-and-mint bridging -- ERC-1155 shares are held in escrow on the source chain while equivalent wrapped tokens are minted on the destination chain, maintaining a 1:1 invariant via `totalLocked` and `totalBridged` counters.

### Bridge In (BSC -> Polygon)

```
User calls OpinionEscrow.lock()
  ├─ totalLocked[tokenId] += amount
  ├─ IERC1155.safeTransferFrom(user -> escrow)        *shares now held in escrow*
  └─ _lzSend(polygonEid, payload)                     *LZ message dispatched*
       └─ BridgeReceiver._lzReceive()                 *on Polygon, via LZ endpoint*
            ├─ totalBridged[tokenId] += amount
            └─ WrappedPredictionToken.mint(recipient)  *wrapped shares minted*
```

### Bridge Back (Polygon -> BSC)

```
User calls BridgeReceiver.bridgeBack()
  ├─ totalBridged[tokenId] -= amount
  ├─ WrappedPredictionToken.burn(user)                *wrapped shares destroyed*
  └─ _lzSend(bscEid, payload)                        *LZ message dispatched*
       └─ OpinionEscrow._lzReceive()                  *on BSC, via LZ endpoint*
            ├─ totalLocked[tokenId] -= amount
            └─ IERC1155.safeTransferFrom(escrow -> user) *original shares released*
```

### Rescue (Admin)

```
Owner calls rescueTokens() / rescueERC20() / rescueETH()
  ├─ Validates _to != address(0)
  ├─ For ERC-1155: blocks rescue if token == escrowedContract && totalLocked[id] > 0
  └─ Transfers tokens/ETH to _to
```

---

## 2. Threat & Trust Model

### Protocol Threat Profile

> Protocol classified as: **Bridge** with no secondary characteristics

Lock-and-mint bridge pattern using LayerZero V2 OApp for cross-chain messaging between BSC and Polygon. Detection signals: cross-chain message passing, lock/unlock pattern, chain ID peer verification, message nonce (LZ-managed).

### Actors & Adversary Model

| Actor | Trust Level | Capabilities |
|-------|-------------|-------------|
| Owner | Trusted | pause/unpause lock and bridgeBack, set destination gas limits, set LZ peers, rescue any tokens not tracked in totalLocked/totalBridged, transfer ownership (2-step via OApp). All operational functions execute instantly -- no timelock or delay on any action. |
| Bridge (WrappedPredictionToken) | Bounded (immutable once set) | mint and burn wrapped ERC-1155 tokens. Set once via setBridge(), cannot be changed. |
| LZ Endpoint | Bounded (external infrastructure) | Deliver cross-chain messages to `_lzReceive`. Peer verification enforced by OApp base -- only messages from configured peer are accepted. |
| User | Untrusted | Lock ERC-1155 shares (requires prior approval), bridge back wrapped tokens (requires balance), provide LZ messaging fee as msg.value. |

**Adversary Ranking** (ordered by threat level for bridge protocols):

1. **Compromised owner** -- Single EOA owner controls all admin functions instantly (pause, rescue, peer configuration) with no timelock or multisig enforcement in code.
2. **LayerZero infrastructure compromise** -- LZ endpoint/relayer set controls cross-chain message delivery; a compromise could forge lock/unlock messages.
3. **Message replay attacker** -- Could attempt to replay valid cross-chain messages to double-mint or double-unlock tokens (mitigated by LZ nonce management).
4. **ERC-1155 callback reentrancy** -- `safeTransferFrom` triggers `onERC1155Received` callbacks; a malicious ERC-1155 contract could attempt reentrancy (mitigated by `nonReentrant`).

See [entry-points.md](entry-points.md) for the full permissionless entry point map.

### Trust Boundaries

1. **Owner <-> Protocol**: Owner can pause user-facing operations, change LZ peers (redirecting cross-chain messages), set gas limits, and rescue non-locked tokens. All actions are instant with no delay. If owner key is compromised, attacker can: redirect bridge messages via `setPeer`, pause `lock`/`bridgeBack` to trap funds on one chain, rescue ERC-20/ETH/untracked ERC-1155 from contracts.

2. **LZ Endpoint <-> Protocol**: Cross-chain messages are accepted only from the LZ endpoint and only from the configured peer. The OApp base enforces peer verification. The trust assumption is that LZ infrastructure faithfully relays messages and prevents forgery/replay.

3. **BridgeReceiver <-> WrappedPredictionToken**: The bridge address is set once (irreversible). Only the bridge can mint/burn. This boundary is strong once established but vulnerable during the window between WrappedPredictionToken deployment and `setBridge()` call.

### Key Attack Surfaces

- **Owner compromise (no timelock)** -- Owner can `setPeer` to redirect all cross-chain messages to an attacker-controlled contract, effectively stealing all locked funds. `rescueETH`/`rescueERC20` can drain non-ERC-1155 assets immediately. No timelock, no multisig enforced in code. Contracts: `OpinionEscrow`, `PredictFunEscrow`, `BridgeReceiver` -- all `onlyOwner` functions.

- **Peer misconfiguration** -- `setPeer` (inherited from OApp) accepts any bytes32 peer address with no validation. Setting wrong peer silently breaks the bridge or opens it to a malicious counterparty. This is a one-shot critical operation during deployment.

- **ERC-1155 safeTransferFrom callback surface** -- `lock()` calls `IERC1155.safeTransferFrom` which triggers `onERC1155Received` on the escrow. A malicious ERC-1155 contract (if one is ever paired) could exploit callbacks. Mitigated by `nonReentrant` on `lock()` and `_lzReceive()`, and by the fact that the ERC-1155 contract address is immutable.

- **totalLocked accounting vs actual balance divergence** -- `totalLocked` is incremented before `safeTransferFrom` in `lock()`. If the transfer fails (reverts), the transaction reverts atomically, so no divergence. However, direct ERC-1155 transfers to the escrow (not via `lock()`) increase actual balance without incrementing `totalLocked` -- these tokens become rescuable by owner.

- **Rescue function token ID granularity** -- `rescueTokens` blocks rescue when `totalLocked[_tokenId] > 0` for the escrowed contract, but does not compare amounts. If `totalLocked[42] == 100` and escrow holds 150 of tokenId 42 (50 sent directly), owner cannot rescue the extra 50 either. This is a conservative design choice, not a vulnerability.

### Protocol-Type Concerns

**As a Bridge:**
- **Cross-chain atomicity gap**: If `lock()` succeeds on BSC but the LZ message fails to deliver on Polygon, tokens are locked in escrow with no wrapped tokens minted. LZ's retry mechanism handles this, but the user's tokens are trapped until the message is retried or the owner intervenes. No on-chain mechanism exists for the user to reclaim tokens if LZ delivery permanently fails.
- **Gas limit enforcement**: `dstGasLimit` sets the minimum gas for `_lzReceive` execution on the destination chain. If set too low, `_lzReceive` reverts on destination, and the message enters LZ's retry queue. No validation prevents setting `dstGasLimit` to 0.
- **Duplicate escrow contracts**: `OpinionEscrow` and `PredictFunEscrow` are near-identical (differing only in naming). Code duplication means a fix applied to one may not be applied to the other.

### Temporal Risk Profile

**Deployment & Initialization:**
- Contracts deploy paused. The window between deploy and `setBridge()`/`setPeer()`/`setDstGasLimit()`/`unpause()` is a multi-step sequence. If `unpause()` is called before `setDstGasLimit()`, users can send messages with no enforced gas floor, risking failed delivery. No on-chain guard prevents this ordering mistake.
- `WrappedPredictionToken.setBridge()` is irreversible. If set to wrong address, the token contract must be redeployed.

### Composability & Dependency Risks

**Dependency Risk Map:**

> **LayerZero V2 OApp** -- via `OpinionEscrow._lzSend()`, `BridgeReceiver._lzReceive()`
> - Assumes: Faithful message relay, replay protection, peer verification, gas-guaranteed execution
> - Validates: Peer check enforced by OApp base; nonce managed by LZ
> - Mutability: LZ endpoint is upgradeable (controlled by LayerZero governance)
> - On failure: Message enters LZ retry queue; user tokens remain locked/burned until retry succeeds

> **Opinion ERC-1155 contract** -- via `OpinionEscrow.lock()`, `OpinionEscrow._lzReceive()`
> - Assumes: Standard ERC-1155 behavior, `safeTransferFrom` transfers exact amount
> - Validates: None -- immutable address set at construction
> - Mutability: Unknown -- depends on the external ERC-1155 implementation
> - On failure: Transaction reverts atomically

> **PredictFun ERC-1155 contract** -- via `PredictFunEscrow.lock()`, `PredictFunEscrow._lzReceive()`
> - Assumes: Standard ERC-1155 behavior, `safeTransferFrom` transfers exact amount
> - Validates: None -- immutable address set at construction
> - Mutability: Unknown -- depends on the external ERC-1155 implementation
> - On failure: Transaction reverts atomically

**Token Assumptions:**
- ERC-1155 shares: assumes standard transfer behavior (exact amount transferred). If the underlying ERC-1155 implements non-standard transfer logic (fee-on-transfer, pausable), the `totalLocked` counter would diverge from actual balance.

---

## 3. Invariants

### Stated Invariants

- `totalBridged[tokenId] == WrappedPredictionToken.totalSupply(tokenId)` at all times. Source: `BridgeReceiver.sol:38-39` NatSpec.
- `totalSupply[tokenId] == BridgeReceiver.totalBridged[tokenId]` at all times. Source: `WrappedPredictionToken.sol:23` NatSpec.
- `totalLocked[id] >= amount` in any unlock message. Source: `OpinionEscrow.sol:54` NatSpec.

### Inferred Invariants

- **Lock-mint symmetry**: For every `lock()` call that succeeds on BSC, exactly one corresponding `_lzReceive()` must execute on Polygon, minting the same `(tokenId, amount)`. Derived from `OpinionEscrow.lock()` + `BridgeReceiver._lzReceive()`. If violated: wrapped tokens exist without backing, or locked tokens have no wrapped representation.
- **Burn-unlock symmetry**: For every `bridgeBack()` call on Polygon, exactly one `_lzReceive()` must execute on BSC, releasing the same `(tokenId, amount)`. Derived from `BridgeReceiver.bridgeBack()` + `OpinionEscrow._lzReceive()`. If violated: tokens burned but never unlocked (lost funds), or unlocked without burn (unbacked unlock).
- **Bridge immutability**: `WrappedPredictionToken.bridge` can only be set once. Derived from `setBridge()` with `BridgeAlreadySet` check. If violated: mint/burn authority transferred to unauthorized address.
- **Escrow solvency**: `IERC1155(opinionContract).balanceOf(escrow, tokenId) >= totalLocked[tokenId]` for all token IDs. Derived from lock/unlock flow. If violated: unlock messages would fail, trapping wrapped tokens on Polygon.

---

## 4. Documentation Quality

| Aspect | Status | Notes |
|--------|--------|-------|
| README | Present | README.md -- deployment guide with architecture diagrams |
| NatSpec | ~4 annotations per contract | Good coverage on functions and state variables; all public/external functions documented |
| Spec/Whitepaper | Missing | No formal specification document |
| Inline Comments | Adequate | Deployment checklists, invariant documentation, message flow descriptions in contract headers |

---

## 5. Test Analysis

| Metric | Value | Source |
|--------|-------|--------|
| Test files | 6 | File scan (always reliable) |
| Test functions | 52 | File scan (always reliable) |
| Line coverage | 46.3% (source only) | Coverage tool -- 81/175 source lines |
| Branch coverage | 32.4% (source only) | Coverage tool -- 12/37 source branches |

Source-file coverage breakdown:
| Contract | Lines | Branches |
|----------|-------|----------|
| BridgeReceiver | 60.42% | 30.00% |
| OpinionEscrow | 61.11% | 30.00% |
| PredictFunEscrow | **0.00%** | **0.00%** |
| WrappedPredictionToken | 100.00% | 85.71% |

### Test Depth

| Category | Count | Contracts Covered |
|----------|-------|-------------------|
| Unit | 46 | BridgeReceiver, OpinionEscrow, WrappedPredictionToken |
| Integration | 6 | BridgeIntegration (full round-trip flows) |
| Stateless Fuzz | 0 | none |
| Stateful Fuzz (Foundry) | 0 | none |
| Formal Verification (Certora) | 0 | none |
| Formal Verification (Halmos) | 0 | none |

### Gaps

- **PredictFunEscrow has zero test coverage** -- this is a near-identical copy of OpinionEscrow but with no tests at all. Any divergence from OpinionEscrow introduced during copy-paste is completely unverified.
- **No fuzz testing** -- lock/unlock flows with varied tokenIds and amounts are prime candidates for stateless fuzz testing to verify accounting invariants.
- **No stateful invariant testing** -- the core invariant (`totalLocked == escrowed balance`, `totalBridged == totalSupply`) should be verified under arbitrary sequences of lock/unlock/bridgeBack operations.
- **Branch coverage at 30%** for tested contracts -- admin rescue paths and error conditions are partially uncovered.
- **No fork testing** -- no tests against live BSC/Polygon LZ endpoints.

---

## 6. Developer & Git History

> Repo shape: normal_dev -- Normal development history with 5 source-touching commits over 24 days

> Analyzed branch: `main` at `44cea07`

### Contributors

| Author | Commits | Source Lines (+/-) | % of Source Changes |
|--------|--------:|--------------------|--------------------:|
| Iurii | 11 | +1101 / -103 | 100% |

Single developer -- 100% of all code authored by one contributor.

### Review & Process Signals

| Signal | Value | Assessment |
|--------|-------|------------|
| Unique contributors | 1 | Single-dev |
| Merge commits | 1 of 11 (9%) | No merge commits on source files -- likely no peer review |
| Repo age | 2026-03-20 -> 2026-04-13 | 24 days |
| Recent source activity (30d) | 5 commits | Active -- all source commits within last 30 days |
| Test co-change rate | 60% | 3 of 5 source-changing commits also modify test files |

### File Hotspots

| File | Modifications | Note |
|------|-------------:|------|
| src/OpinionEscrow.sol | 4 | High churn -- prioritize review |
| src/BridgeReceiver.sol | 4 | High churn -- prioritize review |
| src/WrappedPredictionToken.sol | 2 | Renamed from WrappedOpinionToken |
| src/PredictFunEscrow.sol | 1 | Added late, zero tests |

### Security-Relevant Commits

| SHA | Date | Subject | Score | Key Signal |
|-----|------|---------|------:|------------|
| 5715f1e | 2026-03-20 | first commit | 17 | Initial codebase: adds runtime guards, access control, fund flows across 3 source files |
| 44cea07 | 2026-04-13 | added PredictFunEscrow with correct naming | 16 | New escrow contract spanning 4 security domains, no test co-change |
| 90d3795 | 2026-04-07 | added reentrancy guard | 16 | Explicit security fix: adds ReentrancyGuard to BridgeReceiver and OpinionEscrow |
| 82b4dfc | 2026-04-07 | updated dstGasSet function. Added notations | 15 | Rewrites access control and runtime guards across 3 files |

### Dangerous Area Evolution

| Security Area | Commits | Key Files |
|--------------|--------:|-----------|
| access_control | 5 | OpinionEscrow, BridgeReceiver, PredictFunEscrow |
| fund_flows | 5 | OpinionEscrow, BridgeReceiver, PredictFunEscrow |
| signatures | 5 | OpinionEscrow, BridgeReceiver, PredictFunEscrow |
| state_machines | 5 | OpinionEscrow, BridgeReceiver, PredictFunEscrow |

All security areas touched by every source-changing commit -- consistent with active development of a small codebase.

### Forked Dependencies

| Library | Path | Upstream | Status | Notes |
|---------|------|----------|--------|-------|
| openzeppelin-contracts | lib/openzeppelin-contracts | OpenZeppelin | Submodule | Pragma range includes legacy versions (>=0.4.11) alongside ^0.8.x -- normal for OZ repo |
| LayerZero-v2 | lib/LayerZero-v2 | LayerZero | Submodule | Standard submodule, 249 sol files |
| devtools | lib/devtools | LayerZero | Submodule | LZ development tooling, 424 sol files |
| solidity-bytes-utils | lib/solidity-bytes-utils | GNSPS | Submodule | Standard submodule |

All dependencies are standard git submodules, none internalized.

### Security Observations

- **Single-developer risk**: 100% of code authored by one contributor with no evidence of peer review (no merge commits on source changes).
- **PredictFunEscrow added without tests**: The most recent source commit (44cea07) adds a complete escrow contract with zero accompanying tests and no test co-change.
- **Reentrancy guard added retroactively**: Commit 90d3795 explicitly adds ReentrancyGuard, indicating the original code launched without it -- the fix has no accompanying tests.
- **High churn on security-critical contracts**: OpinionEscrow and BridgeReceiver each modified 4 times in 24 days, with access control and fund flow changes in every commit.
- **40% of source commits lack test changes**: 2 of 5 source-touching commits have no test file modifications.

### Cross-Reference Synthesis

- OpinionEscrow and BridgeReceiver are flagged in both Threat Model (bridge attack surfaces) AND git history (highest modification count, 4 each) -- prioritize for deep review.
- PredictFunEscrow is a near-duplicate of OpinionEscrow added in the most recent commit without tests -- any copy-paste divergence is unverified, amplifying the accounting attack surface identified in Section 2.
- The reentrancy guard fix (commit 90d3795, score 16) was added without tests -- residual risk that the guard placement is incomplete or that a reentrancy vector was missed.
- All four security domains show maximum churn (5/5 commits) -- the entire codebase is security-sensitive with no "cold" zones.

---

## X-Ray Verdict

**FRAGILE** -- Unit tests exist but lack fuzz/invariant testing, one contract has zero coverage, and all admin operations are instant with no timelock.

**Structural facts:**
1. 430 nSLOC across 4 contracts in 2 subsystems (BSC escrow + Polygon bridge/token)
2. Single developer authored 100% of code with no evidence of peer review
3. PredictFunEscrow (132 nSLOC, 31% of codebase) has 0% test coverage
4. No timelock or multisig enforced in any contract -- all owner operations are instant
5. 52 unit/integration tests exist with 46% source line coverage; no fuzz, invariant, or formal verification testing
