// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";

/// @notice Read-only script to inspect LayerZero ULN and Executor configuration
///         for both OpinionEscrow (BSC) and BridgeReceiver (Polygon).
///         Use after SetConfig.s.sol to verify settings were applied correctly.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   OPINION_ESCROW_ADDRESS    OpinionEscrow contract on BSC
///   BRIDGE_RECEIVER_ADDRESS   BridgeReceiver contract on Polygon
///   BSC_LZ_ENDPOINT           LayerZero endpoint on BSC
///   POLYGON_LZ_ENDPOINT       LayerZero endpoint on Polygon
///   BSC_EID                   LayerZero endpoint ID for BSC    (mainnet: 30102)
///   POLYGON_EID               LayerZero endpoint ID for Polygon (mainnet: 30109)
///   BSC_SEND_LIB              Send message lib address on BSC
///   BSC_RECEIVE_LIB           Receive message lib address on BSC
///   POLYGON_SEND_LIB          Send message lib address on Polygon
///   POLYGON_RECEIVE_LIB       Receive message lib address on Polygon
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///
///   Polygon receive config (DVNs watching BSC → Polygon messages):
///     forge script script/integration_tests/GetConfig.s.sol:GetConfigScript \
///       --sig "getPolygonReceive()" --rpc-url $POLYGON_RPC_URL
///
///   Polygon send config (executor + DVNs for Polygon → BSC messages):
///     forge script script/integration_tests/GetConfig.s.sol:GetConfigScript \
///       --sig "getPolygonSend()" --rpc-url $POLYGON_RPC_URL
///
///   BSC send config (executor + DVNs for BSC → Polygon messages):
///     forge script script/integration_tests/GetConfig.s.sol:GetConfigScript \
///       --sig "getBSCSend()" --rpc-url $BSC_RPC_URL
///
///   BSC receive config (DVNs watching Polygon → BSC messages):
///     forge script script/integration_tests/GetConfig.s.sol:GetConfigScript \
///       --sig "getBSCReceive()" --rpc-url $BSC_RPC_URL
///
/// ─── Config type IDs ─────────────────────────────────────────────────────────
///
///   1 = ExecutorConfig  (maxMessageSize, executor address)
///   2 = UlnConfig       (confirmations, required DVNs, optional DVNs)

contract GetConfigScript is Script {

    // ─── Polygon ──────────────────────────────────────────────────────────────

    /// @notice Print ULN config for incoming BSC → Polygon messages.
    ///         Shows which DVNs must confirm messages before BridgeReceiver._lzReceive executes.
    function getPolygonReceive() external view {
        address endpoint = vm.envAddress("POLYGON_LZ_ENDPOINT");
        address oapp     = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        address lib      = vm.envAddress("POLYGON_RECEIVE_LIB");
        uint32  eid      = uint32(vm.envUint("BSC_EID"));

        console.log("=== Polygon Receive (BSC -> Polygon) ===");
        console.log("OApp (BridgeReceiver) :", oapp);
        console.log("Receive lib           :", lib);
        console.log("Source EID (BSC)      :", eid);
        _printULN(endpoint, oapp, lib, eid);
    }

    /// @notice Print ULN + Executor config for outgoing Polygon → BSC messages.
    ///         Shows which DVNs confirm and which executor delivers to OpinionEscrow.
    function getPolygonSend() external view {
        address endpoint = vm.envAddress("POLYGON_LZ_ENDPOINT");
        address oapp     = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        address lib      = vm.envAddress("POLYGON_SEND_LIB");
        uint32  eid      = uint32(vm.envUint("BSC_EID"));

        console.log("=== Polygon Send (Polygon -> BSC) ===");
        console.log("OApp (BridgeReceiver) :", oapp);
        console.log("Send lib              :", lib);
        console.log("Destination EID (BSC) :", eid);
        _printULN(endpoint, oapp, lib, eid);
        _printExecutor(endpoint, oapp, lib, eid);
    }

    // ─── BSC ──────────────────────────────────────────────────────────────────

    /// @notice Print ULN + Executor config for outgoing BSC → Polygon messages.
    ///         Shows which DVNs confirm and which executor delivers to BridgeReceiver.
    function getBSCSend() external view {
        address endpoint = vm.envAddress("BSC_LZ_ENDPOINT");
        address oapp     = vm.envAddress("OPINION_ESCROW_ADDRESS");
        address lib      = vm.envAddress("BSC_SEND_LIB");
        uint32  eid      = uint32(vm.envUint("POLYGON_EID"));

        console.log("=== BSC Send (BSC -> Polygon) ===");
        console.log("OApp (OpinionEscrow)      :", oapp);
        console.log("Send lib                  :", lib);
        console.log("Destination EID (Polygon) :", eid);
        _printULN(endpoint, oapp, lib, eid);
        _printExecutor(endpoint, oapp, lib, eid);
    }

    /// @notice Print ULN config for incoming Polygon → BSC messages.
    ///         Shows which DVNs must confirm messages before OpinionEscrow._lzReceive executes.
    function getBSCReceive() external view {
        address endpoint = vm.envAddress("BSC_LZ_ENDPOINT");
        address oapp     = vm.envAddress("OPINION_ESCROW_ADDRESS");
        address lib      = vm.envAddress("BSC_RECEIVE_LIB");
        uint32  eid      = uint32(vm.envUint("POLYGON_EID"));

        console.log("=== BSC Receive (Polygon -> BSC) ===");
        console.log("OApp (OpinionEscrow)    :", oapp);
        console.log("Receive lib             :", lib);
        console.log("Source EID (Polygon)    :", eid);
        _printULN(endpoint, oapp, lib, eid);
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    /// @dev Decode and print ULN config (config type 2).
    ///      Shows block confirmations required and all required DVN addresses.
    function _printULN(address endpoint, address oapp, address lib, uint32 eid) internal view {
        bytes memory config = ILayerZeroEndpointV2(endpoint).getConfig(oapp, lib, eid, 2);
        UlnConfig memory uln = abi.decode(config, (UlnConfig));

        console.log("-- ULN Config --");
        console.log("Confirmations      :", uln.confirmations);
        console.log("Required DVN count :", uln.requiredDVNCount);
        for (uint256 i = 0; i < uln.requiredDVNs.length; i++) {
            console.log("Required DVN [", i, "] :");
            console.logAddress(uln.requiredDVNs[i]);
        }
    }

    /// @dev Decode and print Executor config (config type 1).
    ///      Shows max message size and executor address.
    function _printExecutor(address endpoint, address oapp, address lib, uint32 eid) internal view {
        bytes memory config = ILayerZeroEndpointV2(endpoint).getConfig(oapp, lib, eid, 1);
        ExecutorConfig memory exec = abi.decode(config, (ExecutorConfig));

        console.log("-- Executor Config --");
        console.log("Max message size :", exec.maxMessageSize);
        console.log("Executor         :", exec.executor);
    }
}