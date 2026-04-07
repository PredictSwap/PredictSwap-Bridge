// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

/// @notice Configures LayerZero send/receive libraries, DVNs, and executor
///         for OpinionEscrow (BSC) and BridgeReceiver (Polygon).
///         Run after deployment and before SetPeers.s.sol.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   DEPLOYER_PRIVATE_KEY      Must be owner of the OApp being configured
///   OPINION_ESCROW_ADDRESS    OpinionEscrow contract on BSC
///   BRIDGE_RECEIVER_ADDRESS   BridgeReceiver contract on Polygon
///   BSC_LZ_ENDPOINT           LayerZero endpoint on BSC
///   POLYGON_LZ_ENDPOINT       LayerZero endpoint on Polygon
///   BSC_EID                   LayerZero endpoint ID for BSC     (mainnet: 30102)
///   POLYGON_EID               LayerZero endpoint ID for Polygon  (mainnet: 30109)
///   BSC_SEND_LIB              Send message lib address on BSC
///   BSC_RECEIVE_LIB           Receive message lib address on BSC
///   BSC_DVN                   DVN address on BSC
///   BSC_EXECUTOR              Executor address on BSC
///   POLYGON_SEND_LIB          Send message lib address on Polygon
///   POLYGON_RECEIVE_LIB       Receive message lib address on Polygon
///   POLYGON_DVN               DVN address on Polygon
///   POLYGON_EXECUTOR          Executor address on Polygon
///
/// ─── What this configures ────────────────────────────────────────────────────
///
///   Send lib    — which message lib handles outbound LZ messages
///   Receive lib — which message lib handles inbound LZ messages
///   ULN config  — block confirmations + required DVNs for message verification
///   Executor    — which executor delivers messages on the destination chain
///
///   Config type IDs:
///     1 = ExecutorConfig  (maxMessageSize, executor address)
///     2 = UlnConfig       (confirmations, required DVNs, optional DVNs)
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///
///   BSC (configure OpinionEscrow send + receive):
///     forge script script/integration_tests/SetConfig.s.sol:SetConfig \
///       --sig "SetLibrariesBSC()" --rpc-url $BSC_RPC_URL --broadcast
///
///   Polygon (configure BridgeReceiver send + receive):
///     forge script script/integration_tests/SetConfig.s.sol:SetConfig \
///       --sig "SetLibrariesPolygon()" --rpc-url $POLYGON_RPC_URL --broadcast
///
/// ─── Verify after running ────────────────────────────────────────────────────
///
///   Run GetConfig.s.sol to confirm settings were applied correctly.

contract SetConfig is Script {

    // ─── Constants ────────────────────────────────────────────────────────────

    uint32 constant EXECUTOR_CONFIG_TYPE = 1;
    uint32 constant ULN_CONFIG_TYPE      = 2;

    /// @dev Block confirmations required before a message is considered verified.
    ///      5 is standard for BSC and Polygon. Increase for higher security.
    uint64 constant CONFIRMATIONS = 5;

    /// @dev Maximum message payload size in bytes.
    uint32 constant MAX_MESSAGE_SIZE = 10_000;

    // ─── State ────────────────────────────────────────────────────────────────

    uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    // ─── BSC ──────────────────────────────────────────────────────────────────

    /// @notice Configure send and receive libraries, DVN, and executor
    ///         for OpinionEscrow on BSC.
    ///         Send:    BSC → Polygon (lock messages)
    ///         Receive: Polygon → BSC (unlock messages)
    function SetLibrariesBSC() external {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(vm.envAddress("BSC_LZ_ENDPOINT"));

        address oapp       = vm.envAddress("OPINION_ESCROW_ADDRESS");
        address sendLib    = vm.envAddress("BSC_SEND_LIB");
        address receiveLib = vm.envAddress("BSC_RECEIVE_LIB");
        address dvn        = vm.envAddress("BSC_DVN");
        address executor   = vm.envAddress("BSC_EXECUTOR");
        uint32  dstEid     = uint32(vm.envUint("POLYGON_EID"));

        (
            SetConfigParam[] memory sendParams,
            SetConfigParam[] memory receiveParams
        ) = _buildParams(dstEid, dvn, executor);

        console.log("=== SetConfig BSC ===");
        console.log("OApp (OpinionEscrow)      :", oapp);
        console.log("Destination EID (Polygon) :", dstEid);
        console.log("Send lib                  :", sendLib);
        console.log("Receive lib               :", receiveLib);
        console.log("DVN                       :", dvn);
        console.log("Executor                  :", executor);
        console.log("Confirmations             :", CONFIRMATIONS);

        vm.startBroadcast(deployerKey);
        endpoint.setSendLibrary(oapp, dstEid, sendLib);
        endpoint.setReceiveLibrary(oapp, dstEid, receiveLib, 0);
        endpoint.setConfig(oapp, sendLib, sendParams);
        endpoint.setConfig(oapp, receiveLib, receiveParams);
        vm.stopBroadcast();

        console.log("Done. run GetConfig.s.sol:getBSCSend / getBSCReceive to verify.");
    }

    // ─── Polygon ──────────────────────────────────────────────────────────────

    /// @notice Configure send and receive libraries, DVN, and executor
    ///         for BridgeReceiver on Polygon.
    ///         Send:    Polygon → BSC (bridge-back messages)
    ///         Receive: BSC → Polygon (lock confirmation messages)
    function SetLibrariesPolygon() external {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(vm.envAddress("POLYGON_LZ_ENDPOINT"));

        address oapp       = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        address sendLib    = vm.envAddress("POLYGON_SEND_LIB");
        address receiveLib = vm.envAddress("POLYGON_RECEIVE_LIB");
        address dvn        = vm.envAddress("POLYGON_DVN");
        address executor   = vm.envAddress("POLYGON_EXECUTOR");
        uint32  dstEid     = uint32(vm.envUint("BSC_EID"));

        (
            SetConfigParam[] memory sendParams,
            SetConfigParam[] memory receiveParams
        ) = _buildParams(dstEid, dvn, executor);

        console.log("=== SetConfig Polygon ===");
        console.log("OApp (BridgeReceiver) :", oapp);
        console.log("Destination EID (BSC) :", dstEid);
        console.log("Send lib              :", sendLib);
        console.log("Receive lib           :", receiveLib);
        console.log("DVN                   :", dvn);
        console.log("Executor              :", executor);
        console.log("Confirmations         :", CONFIRMATIONS);

        vm.startBroadcast(deployerKey);
        endpoint.setSendLibrary(oapp, dstEid, sendLib);
        endpoint.setReceiveLibrary(oapp, dstEid, receiveLib, 0);
        endpoint.setConfig(oapp, sendLib, sendParams);
        endpoint.setConfig(oapp, receiveLib, receiveParams);
        vm.stopBroadcast();

        console.log("Done. run GetConfig.s.sol:getPolygonSend / getPolygonReceive to verify.");
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    /// @dev Builds send (ULN + Executor) and receive (ULN only) config param arrays.
    ///      Extracted to avoid duplicating struct construction across both functions.
    function _buildParams(
        uint32 dstEid,
        address dvn,
        address executor
    ) internal pure returns (
        SetConfigParam[] memory sendParams,
        SetConfigParam[] memory receiveParams
    ) {
        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = dvn;

        UlnConfig memory uln = UlnConfig({
            confirmations:       CONFIRMATIONS,
            requiredDVNCount:    1,
            optionalDVNCount:    0,
            optionalDVNThreshold: 0,
            requiredDVNs:        requiredDVNs,
            optionalDVNs:        new address[](0)
        });

        ExecutorConfig memory exec = ExecutorConfig({
            maxMessageSize: MAX_MESSAGE_SIZE,
            executor:       executor
        });

        // Send config: ULN + Executor
        sendParams = new SetConfigParam[](2);
        sendParams[0] = SetConfigParam(dstEid, EXECUTOR_CONFIG_TYPE, abi.encode(exec));
        sendParams[1] = SetConfigParam(dstEid, ULN_CONFIG_TYPE, abi.encode(uln));

        // Receive config: ULN only (executor not needed for inbound)
        receiveParams = new SetConfigParam[](1);
        receiveParams[0] = SetConfigParam(dstEid, ULN_CONFIG_TYPE, abi.encode(uln));
    }
}