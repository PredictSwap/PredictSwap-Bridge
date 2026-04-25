// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PredictionMarketEscrow} from "../src/PredictionMarketEscrow.sol";

/// @notice Deploys PredictionMarketEscrow on BSC.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   DEPLOYER_PRIVATE_KEY  Private key of the deployer wallet (pays gas)
///   OWNER_ADDRESS         Team multisig — will own the contract post-deploy
///   BSC_LZ_ENDPOINT       LayerZero endpoint on BSC (mainnet: 0x1a44076050125825900e736c501f859c50fE728c)
///   PREDICTION_MARKET_CONTRACT      prediction market ERC-1155 contract address on BSC
///   POLYGON_EID           LayerZero endpoint ID for Polygon (mainnet: 30109)
///   DST_GAS_LIMIT         Gas limit for _lzReceive on Polygon (recommended: 200000)
///
/// ─── Post-deploy steps (run separately after Polygon deploy) ─────────────────
///
///   1. escrow.setPeer(polygonEid, bytes32(uint256(uint160(bridgeReceiverAddress))))
///   2. escrow.unpause()
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///
///   forge script script/DeployBSC.s.sol \
///     --rpc-url $BSC_RPC_URL \
///     --broadcast \
///     --verify
///
contract DeployBSC is Script {

    function run() external {
        uint256 deployerKey   = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address lzEndpoint    = vm.envAddress("BSC_LZ_ENDPOINT");
        address owner         = vm.envAddress("OWNER_ADDRESS");
        address predictionMarketContract = vm.envAddress("PREDICTION_MARKET_CONTRACT");
        uint32  polygonEid    = uint32(vm.envUint("POLYGON_EID"));
        uint128 dstGasLimit   = uint128(vm.envUint("DST_GAS_LIMIT"));

        vm.startBroadcast(deployerKey);

        // 1. Deploy — contract starts paused (safe before peer is set)
        PredictionMarketEscrow escrow = new PredictionMarketEscrow(
            lzEndpoint,
            owner,
            predictionMarketContract,
            polygonEid
        );

        // 2. Set enforced gas floor for _lzReceive on Polygon.
        //    Uses setDstGasLimit() which updates both dstGasLimit storage
        //    and OAppOptionsType3 enforced options in one call.
        //    Must be done before unpause — callers with empty _options
        //    would otherwise have no gas floor set.
        escrow.setDstGasLimit(dstGasLimit);

        vm.stopBroadcast();

        console.log("=== BSC Deployment ===");
        console.log("PredictionMarketEscrow    :", address(escrow));
        console.log("Prediction market contract :", predictionMarketContract);
        console.log("Owner            :", owner);
        console.log("LZ Endpoint      :", lzEndpoint);
        console.log("Polygon EID      :", polygonEid);
        console.log("Dst gas limit    :", dstGasLimit);
        console.log("Paused           : true");
        console.log("");
        console.log("=== Next steps ===");
        console.log("1. Deploy Polygon contracts  -> run DeployPolygon.s.sol");
        console.log("2. setPeer on this contract  -> run SetPeer.s.sol");
        console.log("3. setPeer on BridgeReceiver -> run SetPeer.s.sol");
        console.log("4. unpause both contracts    -> run Unpause.s.sol");
    }
}