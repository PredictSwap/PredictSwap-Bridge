# Security Review — Prediction Market NFT Bridge

---

## Scope

|                                  |                                                        |
| -------------------------------- | ------------------------------------------------------ |
| **Mode**                         | ALL / default                                          |
| **Files reviewed**               | `BridgeReceiver.sol` · `OpinionEscrow.sol`<br>`PredictFunEscrow.sol` · `WrappedPredictionToken.sol` |
| **Confidence threshold (1-100)** | 80                                                     |

---

## Findings

[75] **1. Fee-on-transfer ERC-1155 would cause escrow insolvency**

`OpinionEscrow.lock` · `PredictFunEscrow.lock` · Confidence: 75

**Description**
`totalLocked[_tokenId] += _amount` is incremented by the user-requested amount before `safeTransferFrom`, not by the actual amount received — if the underlying ERC-1155 applies transfer fees, `totalLocked` becomes inflated relative to actual escrowed balance, causing late bridge-back users to lose funds when the escrow runs out of tokens.

---

[70] **2. Unpause without dstGasLimit allows users to send messages with no gas floor**

`OpinionEscrow.unpause` · `BridgeReceiver.unpause` · `PredictFunEscrow.unpause` · Confidence: 70

**Description**
`unpause()` has no `require(dstGasLimit > 0)` or `require(peers[dstEid] != bytes32(0))` check — if the owner calls `unpause()` before `setDstGasLimit()`, users can send cross-chain messages with no enforced gas floor, causing destination `_lzReceive` to revert and user funds (msg.value for LZ fee + locked/burned tokens) to be stuck in LayerZero's retry queue.

---

Findings List

| # | Confidence | Title |
|---|---|---|
| 1 | [75] | Fee-on-transfer ERC-1155 would cause escrow insolvency |
| 2 | [70] | Unpause without dstGasLimit allows users to send messages with no gas floor |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives — they are high-signal leads for manual review. Not scored._

- **Over-restrictive rescue guard traps accidentally-sent tokens** — `OpinionEscrow.rescueTokens`, `PredictFunEscrow.rescueTokens`, `BridgeReceiver.rescueTokens` — Code smells: binary `totalLocked[_tokenId] > 0` / `totalBridged[_tokenId] > 0` check instead of balance-based comparison — Owner cannot rescue accidentally-sent tokens for any tokenId that has outstanding locks, even if the contract holds surplus tokens above `totalLocked`. Tokens trapped until all bridge-backs for that tokenId complete.

- **Reverting recipient permanently blocks unlock message** — `OpinionEscrow._lzReceive`, `PredictFunEscrow._lzReceive` — Code smells: `safeTransferFrom` to user-specified `bscRecipient` triggers `onERC1155Received` callback with no pull-pattern fallback — A `bscRecipient` that reverts on ERC-1155 receipt causes the unlock LZ message to permanently fail on retry. Wrapped tokens are already burned on Polygon. Primarily self-harm but also affects legitimate users who specify a contract address that later becomes unable to receive ERC-1155 (e.g., upgraded proxy).

- **No rate limiting on bridge mint path** — `BridgeReceiver._lzReceive` — Code smells: no per-message/per-block cap, `_lzReceive` intentionally bypasses `whenNotPaused` — A compromised BSC peer or owner key compromise allowing `setPeer` redirection would enable unlimited wrapped token minting with no circuit breaker. Owner can only respond by calling `setPeer` to deregister the compromised peer, which is a race condition.

- **Burn-before-send pattern risks permanent fund loss on destination failure** — `BridgeReceiver.bridgeBack` — Code smells: `wrappedToken.burn()` and `totalBridged -= _amount` execute before `_lzSend` — If `_lzSend` succeeds but destination `_lzReceive` permanently fails (recipient always reverts, opinion contract destroyed), tokens are burned on Polygon with no on-chain recovery. LayerZero retry mechanism is the only recourse.

- **LZ default library not pinned** — `OpinionEscrow`, `PredictFunEscrow`, `BridgeReceiver` — Code smells: no `setSendLibrary`/`setReceiveLibrary` calls in deployment flow — Contracts rely on LZ endpoint mutable defaults; a LayerZero governance change to the default message library would silently alter DVN/executor validation behavior.

---

> :warning: This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
