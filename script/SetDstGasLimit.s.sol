// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {OpinionEscrow} from "../src/OpinionEscrow.sol";
import {BridgeReceiver} from "../src/BridgeReceiver.sol";

/// @notice Sets the enforced minimum gas limit for LZ message execution on the destination chain.
///         Must be called on both chains before unpausing — without this, callers passing
///         empty _options have no gas floor and risk failed execution on the destination.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   DEPLOYER_PRIVATE_KEY      Must be owner of the contract being configured
///   OPINION_ESCROW_ADDRESS    OpinionEscrow address on BSC
///   BRIDGE_RECEIVER_ADDRESS   BridgeReceiver address on Polygon
///
/// ─── Gas limit guidance ──────────────────────────────────────────────────────
///
///   BSC target (OpinionEscrow._lzReceive):
///     - totalLocked update + safeTransferFrom ERC-1155
///     - Recommended: 400_000
///
///   Polygon target (BridgeReceiver._lzReceive):
///     - totalBridged update + mint() + ERC-1155 transfer
///     - Recommended: 400_000
///
///   Both values are conservative — increase if execution reverts due to OOG.
///   Callers can always pass higher gas in _options; enforced value is a floor.
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///
///   BSC (sets gas floor for _lzReceive execution on Polygon):
///     forge script script/SetDstGasLimit.s.sol:SetDstGasLimitBSC \
///       --rpc-url $BSC_RPC_URL --broadcast
///
///   Polygon (sets gas floor for _lzReceive execution on BSC):
///     forge script script/SetDstGasLimit.s.sol:SetDstGasLimitPolygon \
///       --rpc-url $POLYGON_RPC_URL --broadcast
///
/// ─── Verify after running ────────────────────────────────────────────────────
///
///   cast call $OPINION_ESCROW "dstGasLimit()" --rpc-url $BSC_RPC_URL
///   cast call $BRIDGE_RECEIVER "dstGasLimit()" --rpc-url $POLYGON_RPC_URL

// ─── BSC ──────────────────────────────────────────────────────────────────────

contract SetDstGasLimitBSC is Script {

    /// @dev Gas limit for BridgeReceiver._lzReceive execution on Polygon.
    uint128 constant DST_GAS_LIMIT = 400_000;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address escrowAddr  = vm.envAddress("OPINION_ESCROW_ADDRESS");

        console.log("=== SetDstGasLimit BSC ===");
        console.log("OpinionEscrow :", escrowAddr);
        console.log("Gas limit     :", DST_GAS_LIMIT);

        vm.startBroadcast(deployerKey);
        OpinionEscrow(payable(escrowAddr)).setDstGasLimit(DST_GAS_LIMIT);
        vm.stopBroadcast();

        console.log("Done. enforced options set for Polygon destination.");
    }
}

// ─── Polygon ──────────────────────────────────────────────────────────────────

contract SetDstGasLimitPolygon is Script {

    /// @dev Gas limit for OpinionEscrow._lzReceive execution on BSC.
    uint128 constant DST_GAS_LIMIT = 400_000;

    function run() external {
        uint256 deployerKey  = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address receiverAddr = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");

        console.log("=== SetDstGasLimit Polygon ===");
        console.log("BridgeReceiver :", receiverAddr);
        console.log("Gas limit      :", DST_GAS_LIMIT);

        vm.startBroadcast(deployerKey);
        BridgeReceiver(payable(receiverAddr)).setDstGasLimit(DST_GAS_LIMIT);
        vm.stopBroadcast();

        console.log("Done. enforced options set for BSC destination.");
    }
}