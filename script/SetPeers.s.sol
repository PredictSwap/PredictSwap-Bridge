// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PredictionMarketEscrow} from "../src/PredictionMarketEscrow.sol";
import {BridgeReceiver} from "../src/BridgeReceiver.sol";

/// @notice Configures LayerZero peers after both chains are deployed.
///         Must be run on both chains before unpausing — without peers set,
///         all LZ messages will be rejected.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   DEPLOYER_PRIVATE_KEY      Must be owner of the contract being configured
///   PREDICTION_MARKET_ESCROW_ADDRESS    PredictionMarketEscrow address on BSC
///   BRIDGE_RECEIVER_ADDRESS   BridgeReceiver address on Polygon
///   POLYGON_EID               LayerZero endpoint ID for Polygon (mainnet: 30109)
///   BSC_EID                   LayerZero endpoint ID for BSC    (mainnet: 30102)
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///
///   BSC (tell PredictionMarketEscrow to trust BridgeReceiver):
///     forge script script/SetPeers.s.sol:SetPeerBSC \
///       --rpc-url $BSC_RPC_URL --broadcast
///
///   Polygon (tell BridgeReceiver to trust PredictionMarketEscrow):
///     forge script script/SetPeers.s.sol:SetPeerPolygon \
///       --rpc-url $POLYGON_RPC_URL --broadcast
///
/// ─── Pre-flight checklist ────────────────────────────────────────────────────
///
///   [ ] PredictionMarketEscrow deployed on BSC        (DeployBSC.s.sol)
///   [ ] BridgeReceiver deployed on Polygon   (DeployPolygon.s.sol)
///   [ ] Both addresses available as env vars
///
/// ─── Post-run checklist ──────────────────────────────────────────────────────
///
///   [ ] Verify peer on BSC:     cast call $PREDICTION_MARKET_ESCROW "peers(uint32)" $POLYGON_EID --rpc-url $BSC_RPC_URL
///   [ ] Verify peer on Polygon: cast call $BRIDGE_RECEIVER "peers(uint32)" $BSC_EID --rpc-url $POLYGON_RPC_URL
///   [ ] Run Unpause.s.sol on both chains once peers are confirmed

// ─── BSC ──────────────────────────────────────────────────────────────────────

contract SetPeerBSC is Script {
    function run() external {
        uint256 deployerKey  = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address escrowAddr   = vm.envAddress("PREDICTION_MARKET_ESCROW_ADDRESS");
        address receiverAddr = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        uint32  polygonEid   = uint32(vm.envUint("POLYGON_EID"));

        bytes32 peerBytes32 = bytes32(uint256(uint160(receiverAddr)));

        console.log("=== SetPeer BSC ===");
        console.log("PredictionMarketEscrow    :", escrowAddr);
        console.log("Peer (Receiver)  :", receiverAddr);
        console.log("Polygon EID      :", polygonEid);
        console.log("Peer bytes32     :");
        console.logBytes32(peerBytes32);

        vm.startBroadcast(deployerKey);
        PredictionMarketEscrow(payable(escrowAddr)).setPeer(polygonEid, peerBytes32);
        vm.stopBroadcast();

        console.log("Done. PredictionMarketEscrow will now accept messages from BridgeReceiver.");
    }
}

// ─── Polygon ──────────────────────────────────────────────────────────────────

contract SetPeerPolygon is Script {
    function run() external {
        uint256 deployerKey  = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address escrowAddr   = vm.envAddress("PREDICTION_MARKET_ESCROW_ADDRESS");
        address receiverAddr = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        uint32  bscEid       = uint32(vm.envUint("BSC_EID"));

        bytes32 peerBytes32 = bytes32(uint256(uint160(escrowAddr)));

        console.log("=== SetPeer Polygon ===");
        console.log("BridgeReceiver   :", receiverAddr);
        console.log("Peer (Escrow)    :", escrowAddr);
        console.log("BSC EID          :", bscEid);
        console.log("Peer bytes32     :");
        console.logBytes32(peerBytes32);

        vm.startBroadcast(deployerKey);
        BridgeReceiver(payable(receiverAddr)).setPeer(bscEid, peerBytes32);
        vm.stopBroadcast();

        console.log("Done. BridgeReceiver will now accept messages from PredictionMarketEscrow.");
    }
}