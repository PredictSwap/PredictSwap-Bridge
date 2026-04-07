// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/// @notice Mock ERC-1155 contract simulating the Opinion token on BSC.
/// @dev    Testnet only — permissionless mint, no access control.
///         Deployed once per testnet session. Address goes into OPINION_CONTRACT env var.
contract MockOpinion is ERC1155 {
    constructor() ERC1155("https://mock.uri/{id}") {}

    /// @notice Mint any token ID to any address — no restrictions.
    /// @param to     Recipient address.
    /// @param id     ERC-1155 token ID to mint.
    /// @param amount Number of tokens to mint.
    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }
}

/// @notice Deploys MockOpinion on BSC testnet to simulate the Opinion ERC-1155 contract.
///         Use the deployed address as OPINION_CONTRACT in all subsequent scripts.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   DEPLOYER_PRIVATE_KEY   Wallet paying deployment gas
///
/// ─── Post-deploy ─────────────────────────────────────────────────────────────
///
///   Copy the logged MockOpinion address into your .env as OPINION_CONTRACT.
///   Then run MintMock.s.sol to fund your wallet with test tokens.
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///
///   forge script script/integration_tests/DeployMockOpinion.s.sol \
///     --rpc-url $BSC_TESTNET_RPC_URL --broadcast --verify
///
contract DeployMockOpinion is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        MockOpinion mock = new MockOpinion();
        vm.stopBroadcast();

        console.log("=== DeployMockOpinion ===");
        console.log("MockOpinion:", address(mock));
        console.log("Set OPINION_CONTRACT=", address(mock));
    }
}