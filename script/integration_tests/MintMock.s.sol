// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

/// @notice Mints mock Opinion ERC-1155 tokens (YES and NO) to a recipient wallet.
///         Used to fund a test wallet before running BridgeTokens.s.sol.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   DEPLOYER_PRIVATE_KEY   Wallet paying gas (must be able to call mint on MockOpinion)
///   OPINION_CONTRACT       MockOpinion contract address on BSC testnet
///   OWNER_ADDRESS          Recipient of the minted tokens
///
/// ─── Notes ───────────────────────────────────────────────────────────────────
///
///   - TOKEN_ID_YES and TOKEN_ID_NO must match the IDs used in BridgeTokens.s.sol
///     and registered in OpinionEscrow.
///   - balanceOf reads happen outside the broadcast (view calls, no gas needed).
///   - Both mints are batched in a single broadcast to save gas.
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///
///   forge script script/integration_tests/MintMock.s.sol \
///     --rpc-url $BSC_TESTNET_RPC_URL --broadcast

interface IMockOpinion {
    function mint(address to, uint256 id, uint256 amount) external;
    function balanceOf(address account, uint256 id) external view returns (uint256);
}

contract MintMock is Script {

    // ─── Config — update if token IDs change ─────────────────────────────────

    /// @dev YES outcome token ID on the Opinion mock contract.
    uint256 constant TOKEN_ID_YES = 68227038457866748595233145251243944054564947305383894629176574093714476769147;

    /// @dev NO outcome token ID on the Opinion mock contract.
    uint256 constant TOKEN_ID_NO  = 23295406450705254064374249781739843340364170407721892525550504746101807113177;

    /// @dev Amount to mint per token ID. Opinion shares use 1e18 precision.
    uint256 constant AMOUNT = 1_000 * 1e18;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address mock        = vm.envAddress("OPINION_CONTRACT");
        address recipient   = vm.envAddress("OWNER_ADDRESS");

        console.log("=== MintMock ===");
        console.log("MockOpinion :", mock);
        console.log("Recipient   :", recipient);
        console.log("Amount each :", AMOUNT);

        // ─── Execute ─────────────────────────────────────────────────────────

        vm.startBroadcast(deployerKey);
        IMockOpinion(mock).mint(recipient, TOKEN_ID_YES, AMOUNT);
        IMockOpinion(mock).mint(recipient, TOKEN_ID_NO, AMOUNT);
        vm.stopBroadcast();

        // ─── Post-mint balance check (view, no gas) ───────────────────────────

        uint256 balYes = IMockOpinion(mock).balanceOf(recipient, TOKEN_ID_YES);
        uint256 balNo  = IMockOpinion(mock).balanceOf(recipient, TOKEN_ID_NO);

        console.log("YES token ID :", TOKEN_ID_YES);
        console.log("YES balance  :", balYes);
        console.log("NO token ID  :", TOKEN_ID_NO);
        console.log("NO balance   :", balNo);
    }
}