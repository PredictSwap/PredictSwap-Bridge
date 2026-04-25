// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

/// @notice Locks prediction market ERC-1155 shares in PredictionMarketEscrow on BSC and sends a
///         LayerZero message to BridgeReceiver on Polygon, which mints WrappedPredictionToken.
///
/// ─── Required env vars ───────────────────────────────────────────────────────
///
///   DEPLOYER_PRIVATE_KEY      Wallet that holds the prediction market ERC-1155 tokens
///   PREDICTION_MARKET_CONTRACT          prediction market ERC-1155 contract address on BSC
///   PREDICTION_MARKET_ESCROW_ADDRESS    PredictionMarketEscrow contract address on BSC
///   OWNER_ADDRESS             Polygon address to receive the minted wrapped tokens
///
/// ─── Notes ───────────────────────────────────────────────────────────────────
///
///   - Caller must hold sufficient prediction market ERC-1155 balance for TOKEN_ID.
///   - setApprovalForAll is granted before lock() and revoked immediately after
///     within the same broadcast, minimizing the approval window.
///   - Empty options are passed — enforced options on PredictionMarketEscrow provide
///     the gas floor (400_000) for BridgeReceiver._lzReceive on Polygon.
///   - Fee is quoted on-chain and padded with a 10% buffer to avoid underpayment.
///     Any excess is refunded to msg.sender by the LZ endpoint.
///   - TOKEN_ID and AMOUNT are hardcoded below — update before running.
///
/// ─── Run ─────────────────────────────────────────────────────────────────────
///
///   forge script script/integration_tests/BridgeTokens.s.sol \
///     --rpc-url $BSC_RPC_URL --broadcast
///
/// ─── Monitor ─────────────────────────────────────────────────────────────────
///
///   https://layerzeroscan.com  (mainnet)
///   https://testnet.layerzeroscan.com  (testnet)

struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

interface IERC1155 {
    function setApprovalForAll(address operator, bool approved) external;
    function balanceOf(address account, uint256 id) external view returns (uint256);
}

interface IPredictionMarketEscrow {
    function quoteLockFee(
        uint256 _tokenId,
        uint256 _amount,
        address _polygonRecipient,
        bytes calldata _options
    ) external view returns (MessagingFee memory fee);

    function lock(
        uint256 _tokenId,
        uint256 _amount,
        address _polygonRecipient,
        bytes calldata _options
    ) external payable;
}

contract BridgeTokens is Script {

    // ─── Config — update before running ──────────────────────────────────────

    /// @dev prediction market ERC-1155 token ID to lock and bridge to Polygon.
    uint256 constant TOKEN_ID = 68227038457866748595233145251243944054564947305383894629176574093714476769147;

    /// @dev Number of tokens to lock. prediction market shares use 1e18 precision.
    uint256 constant AMOUNT = 100 * 1e18;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address predictionMarket = vm.envAddress("PREDICTION_MARKET_CONTRACT");
        address escrow      = vm.envAddress("PREDICTION_MARKET_ESCROW_ADDRESS");
        address self        = vm.envAddress("OWNER_ADDRESS");

        // Empty options — enforced options on PredictionMarketEscrow provide the gas floor
        bytes memory options = new bytes(0);

        // ─── Pre-flight ──────────────────────────────────────────────────────

        uint256 bal = IERC1155(predictionMarket).balanceOf(self, TOKEN_ID);
        console.log("=== BridgeTokens ===");
        console.log("Token ID         :", TOKEN_ID);
        console.log("Amount           :", AMOUNT);
        console.log("Balance on BSC   :", bal);
        require(bal >= AMOUNT, "Insufficient prediction market token balance");

        MessagingFee memory fee = IPredictionMarketEscrow(escrow).quoteLockFee(
            TOKEN_ID, AMOUNT, self, options
        );
        uint256 feeWithBuffer = fee.nativeFee * 110 / 100;
        console.log("LZ fee (wei)     :", fee.nativeFee);
        console.log("Fee + 10% buffer :", feeWithBuffer);

        // ─── Execute ─────────────────────────────────────────────────────────

        vm.startBroadcast(deployerKey);
        IERC1155(predictionMarket).setApprovalForAll(escrow, true);
        IPredictionMarketEscrow(escrow).lock{value: feeWithBuffer}(TOKEN_ID, AMOUNT, self, options);
        IERC1155(predictionMarket).setApprovalForAll(escrow, false);
        vm.stopBroadcast();

        console.log("Bridge tx sent.");
        console.log("Polygon recipient:", self);
        console.log("Monitor          : https://layerzeroscan.com");
    }
}