// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {OpinionEscrow} from "../src/OpinionEscrow.sol";
import {BridgeReceiver} from "../src/BridgeReceiver.sol";

/// @notice Unpauses bridge contracts after all setup steps are complete.
///         This is the final step before the bridge is live — do not run
///         until the entire pre-flight checklist is confirmed on both chains.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   DEPLOYER_PRIVATE_KEY      Must be owner of the contract being unpaused
///   OPINION_ESCROW_ADDRESS    OpinionEscrow address on BSC
///   BRIDGE_RECEIVER_ADDRESS   BridgeReceiver address on Polygon
///
/// ─── Pre-flight checklist (confirm before running) ───────────────────────────
///
///   [ ] OpinionEscrow deployed on BSC            (DeployBSC.s.sol)
///   [ ] BridgeReceiver + WrappedOpinionToken
///       deployed on Polygon                      (DeployPolygon.s.sol)
///   [ ] WrappedOpinionToken.bridge == BridgeReceiver
///       cast call $WRAPPED_TOKEN "bridge()" --rpc-url $POLYGON_RPC_URL
///   [ ] OpinionEscrow peer set to BridgeReceiver (SetPeers.s.sol)
///       cast call $OPINION_ESCROW "peers(uint32)" $POLYGON_EID --rpc-url $BSC_RPC_URL
///   [ ] BridgeReceiver peer set to OpinionEscrow (SetPeers.s.sol)
///       cast call $BRIDGE_RECEIVER "peers(uint32)" $BSC_EID --rpc-url $POLYGON_RPC_URL
///   [ ] dstGasLimit set on OpinionEscrow         (SetDstGasLimit.s.sol)
///       cast call $OPINION_ESCROW "dstGasLimit()" --rpc-url $BSC_RPC_URL
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
///   cast call $OPINION_ESCROW "paused()" --rpc-url $BSC_RPC_URL
///   cast call $BRIDGE_RECEIVER "paused()" --rpc-url $POLYGON_RPC_URL

// ─── BSC ──────────────────────────────────────────────────────────────────────

contract UnpauseBSC is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address escrowAddr  = vm.envAddress("OPINION_ESCROW_ADDRESS");

        console.log("=== Unpause BSC ===");
        console.log("OpinionEscrow :", escrowAddr);

        vm.startBroadcast(deployerKey);
        OpinionEscrow(payable(escrowAddr)).unpause();
        vm.stopBroadcast();

        console.log("Done. OpinionEscrow is live. lock() is now open.");
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