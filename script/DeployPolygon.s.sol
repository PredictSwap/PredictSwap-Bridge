// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {WrappedPredictionToken} from "../src/WrappedPredictionToken.sol";
import {BridgeReceiver} from "../src/BridgeReceiver.sol";

/// @notice Deploys WrappedPredictionToken and BridgeReceiver on Polygon.
///         Must be run after DeployBSC.s.sol — PredictionMarketEscrow address is needed
///         for the setPeer step.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   DEPLOYER_PRIVATE_KEY  Private key of the deployer wallet (pays gas)
///   OWNER_ADDRESS         Team multisig — will own both contracts post-deploy
///   POLYGON_LZ_ENDPOINT   LayerZero endpoint on Polygon (mainnet: 0x1a44076050125825900e736c501f859c50fE728c)
///   PREDICTION_MARKET_CONTRACT      prediction market ERC-1155 contract address on BSC (for WrappedPredictionToken metadata)
///   BSC_EID               LayerZero endpoint ID for BSC (mainnet: 30102)
///   DST_GAS_LIMIT         Gas limit for _lzReceive on BSC (recommended: 150000)
///
/// ─── Post-deploy steps (run separately after both chains deployed) ────────────
///
///   1. bridgeReceiver.setPeer(bscEid, bytes32(uint256(uint160(predictionMarketEscrowAddress))))
///   2. predictionMarketEscrow.setPeer(polygonEid, bytes32(uint256(uint160(bridgeReceiverAddress))))
///   3. unpause both contracts
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///
///   forge script script/DeployPolygon.s.sol \
///     --rpc-url $POLYGON_RPC_URL \
///     --broadcast \
///     --verify
///
contract DeployPolygon is Script {

    function run() external {
        uint256 deployerKey  = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address lzEndpoint   = vm.envAddress("POLYGON_LZ_ENDPOINT");
        address owner        = vm.envAddress("OWNER_ADDRESS");
        address predictionMarketContract = vm.envAddress("PREDICTION_MARKET_CONTRACT");
        uint32  bscEid       = uint32(vm.envUint("BSC_EID"));
        uint128 dstGasLimit  = uint128(vm.envUint("DST_GAS_LIMIT"));

        vm.startBroadcast(deployerKey);

        // 1. Deploy WrappedPredictionToken — no bridge set yet, mint/burn will
        //    revert until setBridge() is called below.
        WrappedPredictionToken wrappedToken = new WrappedPredictionToken(
            owner,
            predictionMarketContract
        );

        // 2. Deploy BridgeReceiver — starts paused (safe before peer and bridge are set).
        BridgeReceiver bridgeReceiver = new BridgeReceiver(
            lzEndpoint,
            owner,
            address(wrappedToken),
            bscEid
        );

        // 3. Wire WrappedPredictionToken to BridgeReceiver — one-time, irreversible.
        //    After this, only BridgeReceiver can mint and burn wrapped tokens.
        wrappedToken.setBridge(address(bridgeReceiver));

        // 4. Set enforced gas floor for _lzReceive on BSC.
        //    Uses setDstGasLimit() which updates both dstGasLimit storage
        //    and OAppOptionsType3 enforced options in one call.
        bridgeReceiver.setDstGasLimit(dstGasLimit);

        vm.stopBroadcast();

        console.log("=== Polygon Deployment ===");
        console.log("WrappedPredictionToken:", address(wrappedToken));
        console.log("BridgeReceiver     :", address(bridgeReceiver));
        console.log("Prediction market contract   :", predictionMarketContract);
        console.log("Owner              :", owner);
        console.log("LZ Endpoint        :", lzEndpoint);
        console.log("BSC EID            :", bscEid);
        console.log("Dst gas limit      :", dstGasLimit);
        console.log("Bridge set         : true");
        console.log("Paused             : true");
        console.log("");
        console.log("=== Next steps ===");
        console.log("1. setPeer on BridgeReceiver -> run SetPeer.s.sol");
        console.log("2. setPeer on PredictionMarketEscrow  -> run SetPeer.s.sol");
        console.log("3. unpause both contracts    -> run Unpause.s.sol");
    }
}