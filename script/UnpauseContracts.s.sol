// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PredictionMarketEscrow} from "../src/PredictionMarketEscrow.sol";
import {BridgeReceiver} from "../src/BridgeReceiver.sol";

/// @notice Unpauses bridge contracts after all setup steps are complete.
///         This is the final step before the bridge is live — do not run
///         until the entire pre-flight checklist is confirmed on both chains.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   DEPLOYER_PRIVATE_KEY      Must be owner of the contract being unpaused
///   PREDICTION_MARKET_ESCROW_ADDRESS    PredictionMarketEscrow address on BSC
///   BRIDGE_RECEIVER_ADDRESS   BridgeReceiver address on Polygon
///
/// ─── Pre-flight checklist (confirm before running) ───────────────────────────
///
///   [ ] PredictionMarketEscrow deployed on BSC            (DeployBSC.s.sol)
///   [ ] BridgeReceiver + WrappedPredictionToken
///       deployed on Polygon                      (DeployPolygon.s.sol)
///   [ ] WrappedPredictionToken.bridge == BridgeReceiver
///       cast call $WRAPPED_TOKEN "bridge()" --rpc-url $POLYGON_RPC_URL
///   [ ] PredictionMarketEscrow peer set to BridgeReceiver (SetPeers.s.sol)
///       cast call $PREDICTION_MARKET_ESCROW "peers(uint32)" $POLYGON_EID --rpc-url $BSC_RPC_URL
///   [ ] BridgeReceiver peer set to PredictionMarketEscrow (SetPeers.s.sol)
///       cast call $BRIDGE_RECEIVER "peers(uint32)" $BSC_EID --rpc-url $POLYGON_RPC_URL
///   [ ] dstGasLimit set on PredictionMarketEscrow         (SetDstGasLimit.s.sol)
///       cast call $PREDICTION_MARKET_ESCROW "dstGasLimit()" --rpc-url $BSC_RPC_URL
///   [ ] dstGasLimit set on BridgeReceiver        (SetDstGasLimit.s.sol)
///       cast call $BRIDGE_RECEIVER "dstGasLimit()" --rpc-url $POLYGON_RPC_URL
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///
///   BSC:
///     forge script script/Unpause.s.sol:UnpauseBSC \
///       --rpc-url $BSC_RPC_URL --broadcast
///
///   Polygon:
///     forge script script/Unpause.s.sol:UnpausePolygon \
///       --rpc-url $POLYGON_RPC_URL --broadcast
///
/// ─── Verify after running ────────────────────────────────────────────────────
///
///   cast call $PREDICTION_MARKET_ESCROW "paused()" --rpc-url $BSC_RPC_URL
///   cast call $BRIDGE_RECEIVER "paused()" --rpc-url $POLYGON_RPC_URL

// ─── BSC ──────────────────────────────────────────────────────────────────────

contract UnpauseBSC is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address escrowAddr  = vm.envAddress("PREDICTION_MARKET_ESCROW_ADDRESS");

        console.log("=== Unpause BSC ===");
        console.log("PredictionMarketEscrow :", escrowAddr);

        vm.startBroadcast(deployerKey);
        PredictionMarketEscrow(payable(escrowAddr)).unpause();
        vm.stopBroadcast();

        console.log("Done. PredictionMarketEscrow is live. lock() is now open.");
    }
}

// ─── Polygon ──────────────────────────────────────────────────────────────────

contract UnpausePolygon is Script {
    function run() external {
        uint256 deployerKey  = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address receiverAddr = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");

        console.log("=== Unpause Polygon ===");
        console.log("BridgeReceiver :", receiverAddr);

        vm.startBroadcast(deployerKey);
        BridgeReceiver(payable(receiverAddr)).unpause();
        vm.stopBroadcast();

        console.log("Done. BridgeReceiver is live. bridgeBack() is now open.");
    }
}