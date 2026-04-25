// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/// @notice Mock ERC-1155 contract simulating the prediction market token on BSC.
/// @dev    Testnet only — permissionless mint, no access control.
///         Deployed once per testnet session. Address goes into PREDICTION_MARKET_CONTRACT env var.
contract MockPredictionMarket is ERC1155 {
    constructor() ERC1155("https://mock.uri/{id}") {}

    /// @notice Mint any token ID to any address — no restrictions.
    /// @param to     Recipient address.
    /// @param id     ERC-1155 token ID to mint.
    /// @param amount Number of tokens to mint.
    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }
}

/// @notice Deploys MockPredictionMarket on BSC testnet to simulate the prediction market ERC-1155 contract.
///         Use the deployed address as PREDICTION_MARKET_CONTRACT in all subsequent scripts.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   DEPLOYER_PRIVATE_KEY   Wallet paying deployment gas
///
/// ─── Post-deploy ─────────────────────────────────────────────────────────────
///
///   Copy the logged MockPredictionMarket address into your .env as PREDICTION_MARKET_CONTRACT.
///   Then run MintMock.s.sol to fund your wallet with test tokens.
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///
///   forge script script/integration_tests/DeployMockPredictionMarket.s.sol \
///     --rpc-url $BSC_TESTNET_RPC_URL --broadcast --verify
///
contract DeployMockPredictionMarket is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        MockPredictionMarket mock = new MockPredictionMarket();
        vm.stopBroadcast();

        console.log("=== DeployMockPredictionMarket ===");
        console.log("MockPredictionMarket:", address(mock));
        console.log("Set PREDICTION_MARKET_CONTRACT=", address(mock));
    }
}