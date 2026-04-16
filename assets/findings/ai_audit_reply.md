# Audit conserns

audit was made by ai tool - https://aiaudit.hashlock.com/audit/d97fbfdf-58a4-4130-a8e4-94b8840914ff

## Responses
1. Critical Accounting Mismatch Vulnerability in Cross-Chain Bridge
LZ has a retry message functionality[https://docs.layerzero.network/v2/developers/evm/troubleshooting/debugging-messages#retry-message]. In rare cases when message was sent but was not executed, there is a process of recovering it.

2. Reentrancy Attack in OpinionEscrow Unlock Flow
Not applicable as ERC1155 contract is defined by the team and cannot be changed. Additionally, CEI order is already satisfied — totalLocked is decremented before the external call. Even if the contract were untrusted, there is no stale state to exploit.

3. Permanent Token Lock Due to Immutable Bridge Configuration
That is made by design. In case any error with bridge we have a way to retrieve "locked" shares by implementiog new contracts

4. Missing Validation of LayerZero Message Origin
Peer validation is made by LZ code

5. Unchecked ETH Transfer Return Value in Rescue Functions
Not applicable

6. Front-Running Attack on Bridge Operations
Nothing to frontrun

7. Integer Overflow in Total Supply Tracking
Not applicable. Solidity 0.8+ reverts on overflow automatically. Additionally totalSupply underflow is prevented structurally — totalBridged check in bridgeBack() gates every burn() call.

8. Gas Limit Misconfiguration Attack
Users can add extra gas via _options on top of dstGasLimit. To prevent upward misconfiguration, a sanity range will be added to setDstGasLimit

9. Centralization Risk with Single Owner Model
Valid

Considering adding seperate guardian role for non-critical parameters (setDstGasLimit, pause) apart from multi-sig wallet for main (setPeer, unpause, setEnforcedOptions) 
```bash
address public guardian; 

modifier onlyGuardian() {
    require(msg.sender == guardian || msg.sender == owner(), "not authorized");
    _;
}

// Routine — guardian can do this
function setDstGasLimit(uint128 _gasLimit) external onlyGuardian { ... }
function pause() external onlyGuardian { ... }

// Critical — owner (multisig) only
function setPeer(...) external onlyOwner { ... }  
function setEnforcedOptions(...) external onlyOwner { ... }
function unpause() external onlyOwner { ... } 
```

Apart of that timelock arrangement for setPeer and other critical function will be considered in next versions

10. Denial of Service via Malicious ERC1155 Receiver
Not applicable

11. Missing Event Emission for Critical State Changes
Not applicable

12. Inefficient Storage Pattern in Mapping Usage
Not applicable


another AI audit report https://app.auditagent.nethermind.io/scan-results/f51f96b8-0b6a-40d7-904a-f4ec2290c8aa
