// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

/// @notice Burns WrappedPredictionToken on Polygon and sends an unlock message to
///         PredictionMarketEscrow on BSC, releasing the original prediction market shares to _bscRecipient.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   DEPLOYER_PRIVATE_KEY            Wallet that holds the wrapped tokens
///   WRAPPED_PREDICTION_TOKEN_ADDRESS   WrappedPredictionToken contract on Polygon
///   BRIDGE_RECEIVER_ADDRESS         BridgeReceiver contract on Polygon
///   OWNER_ADDRESS                   BSC recipient of the unlocked prediction market tokens
///
/// ─── Notes ───────────────────────────────────────────────────────────────────
///
///   - No token approval needed — BridgeReceiver.bridgeBack() burns directly
///     from msg.sender via WrappedPredictionToken.burn(), which is bridge-only.
///   - Empty options are passed — enforced options on BridgeReceiver provide
///     the gas floor (400_000) for PredictionMarketEscrow._lzReceive on BSC.
///   - Fee is quoted on-chain and padded with a 10% buffer to avoid underpayment.
///     Any excess is refunded to msg.sender by the LZ endpoint.
///   - TOKEN ID and AMOUNT are hardcoded below — update before running.
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///
///   forge script script/integration_tests/BridgeBack.s.sol \
///     --rpc-url $POLYGON_RPC_URL --broadcast
///
/// ─── Monitor ─────────────────────────────────────────────────────────────────
///
///   https://layerzeroscan.com  (mainnet)
///   https://testnet.layerzeroscan.com  (testnet)

struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

interface IWrappedToken {
    function balanceOf(address account, uint256 id) external view returns (uint256);
}

interface IBridgeReceiver {
    function quoteBridgeBackFee(
        uint256 _tokenId,
        uint256 _amount,
        address _bscRecipient,
        bytes calldata _options
    ) external view returns (MessagingFee memory fee);

    function bridgeBack(
        uint256 _tokenId,
        uint256 _amount,
        address _bscRecipient,
        bytes calldata _options
    ) external payable;
}

contract BridgeBack is Script {

    // ─── Config — update before running ──────────────────────────────────────

    /// @dev prediction market ERC-1155 token ID to bridge back.
    uint256 constant TOKEN_ID = 68227038457866748595233145251243944054564947305383894629176574093714476769147;

    /// @dev Number of wrapped tokens to burn and bridge back.
    uint256 constant AMOUNT = 50;

    function run() external {
        uint256 deployerKey    = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address wrappedToken   = vm.envAddress("WRAPPED_PREDICTION_TOKEN_ADDRESS");
        address bridgeReceiver = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        address self           = vm.envAddress("OWNER_ADDRESS");

        // Empty options — enforced options on BridgeReceiver provide the gas floor
        bytes memory options = new bytes(0);

        // ─── Pre-flight ──────────────────────────────────────────────────────

        uint256 bal = IWrappedToken(wrappedToken).balanceOf(self, TOKEN_ID);
        console.log("=== BridgeBack ===");
        console.log("Token ID        :", TOKEN_ID);
        console.log("Amount          :", AMOUNT);
        console.log("Wrapped balance :", bal);
        require(bal >= AMOUNT, "Insufficient wrapped token balance");

        MessagingFee memory fee = IBridgeReceiver(bridgeReceiver).quoteBridgeBackFee(
            TOKEN_ID, AMOUNT, self, options
        );
        uint256 feeWithBuffer = fee.nativeFee * 110 / 100;
        console.log("LZ fee (wei)    :", fee.nativeFee);
        console.log("Fee + 10% buffer:", feeWithBuffer);

        // ─── Execute ─────────────────────────────────────────────────────────

        vm.startBroadcast(deployerKey);
        // No approval needed — burn() is called by BridgeReceiver on msg.sender directly
        IBridgeReceiver(bridgeReceiver).bridgeBack{value: feeWithBuffer}(
            TOKEN_ID, AMOUNT, self, options
        );
        vm.stopBroadcast();

        console.log("Bridge back tx sent.");
        console.log("BSC recipient   :", self);
        console.log("Monitor         : https://layerzeroscan.com");
    }
}