// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PredictionMarketEscrow} from "../src/PredictionMarketEscrow.sol";
import {BridgeReceiver} from "../src/BridgeReceiver.sol";
import {WrappedPredictionToken} from "../src/WrappedPredictionToken.sol";
import {MockEndpointV2} from "./mocks/MockEndpointV2.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";

/// @title BridgeIntegrationTest
/// @notice Full end-to-end test simulating cross-chain bridge operations
///         between BSC (PredictionMarketEscrow) and Polygon (BridgeReceiver).
///         Uses MockEndpointV2 to simulate LayerZero message delivery.
contract BridgeIntegrationTest is Test {

    // ─── Chain constants ──────────────────────────────────────────────────────

    uint32 constant BSC_EID     = 30102;
    uint32 constant POLYGON_EID = 30109;

    // ─── Token IDs ────────────────────────────────────────────────────────────

    uint256 constant TOKEN_ID_YES = 1; // "Fed March - 25bps decrease - YES"
    uint256 constant TOKEN_ID_NO  = 2; // "Fed March - 25bps decrease - NO"

    // ─── BSC contracts ────────────────────────────────────────────────────────

    MockEndpointV2 public bscEndpoint;
    PredictionMarketEscrow  public escrow;
    MockERC1155    public predictionMarketToken;

    // ─── Polygon contracts ────────────────────────────────────────────────────

    MockEndpointV2      public polyEndpoint;
    BridgeReceiver      public receiver;
    WrappedPredictionToken public wrappedToken;

    // ─── Actors ───────────────────────────────────────────────────────────────

    address public deployer    = makeAddr("deployer");
    address public alice       = makeAddr("alice");       // Polygon EOA receiving wrapped tokens
    address public aliceBscSafe = makeAddr("aliceBscSafe"); // BSC Safe holding prediction market tokens

    // ─── LZ options ───────────────────────────────────────────────────────────

    bytes public _option = abi.encodePacked(
        uint16(0x0003),
        uint8(0x01),
        uint16(0x0011),
        uint8(0x01),
        uint128(400_000) // matches enforced floor
    );

    function setUp() public {
        // ─── BSC side ─────────────────────────────────────────────────────────
        bscEndpoint  = new MockEndpointV2(BSC_EID);
        predictionMarketToken = new MockERC1155();

        vm.prank(deployer);
        escrow = new PredictionMarketEscrow(address(bscEndpoint), deployer, address(predictionMarketToken), POLYGON_EID);

        // ─── Polygon side ─────────────────────────────────────────────────────
        polyEndpoint = new MockEndpointV2(POLYGON_EID);

        vm.startPrank(deployer);
        wrappedToken = new WrappedPredictionToken(deployer, address(predictionMarketToken));
        receiver     = new BridgeReceiver(address(polyEndpoint), deployer, address(wrappedToken), BSC_EID);

        wrappedToken.setBridge(address(receiver));

        escrow.setPeer(POLYGON_EID, bytes32(uint256(uint160(address(receiver)))));
        receiver.setPeer(BSC_EID,   bytes32(uint256(uint160(address(escrow)))));

        escrow.setDstGasLimit(400_000);
        receiver.setDstGasLimit(400_000);

        escrow.unpause();
        receiver.unpause();
        vm.stopPrank();

        // ─── Fund Alice ───────────────────────────────────────────────────────
        predictionMarketToken.mint(aliceBscSafe, TOKEN_ID_YES, 5000);
        predictionMarketToken.mint(aliceBscSafe, TOKEN_ID_NO,  3000);
        vm.deal(aliceBscSafe, 10 ether);
        vm.deal(alice, 10 ether);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    /// @dev Approve + lock tokens from aliceBscSafe and deliver LZ message to Polygon.
    function _lockAndDeliver(uint256 tokenId, uint256 amount, uint256 msgIndex) internal {
        vm.prank(aliceBscSafe);
        predictionMarketToken.setApprovalForAll(address(escrow), true);

        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(tokenId, amount, alice, _option);

        bscEndpoint.deliverMessage(msgIndex, polyEndpoint);
    }

    // ─── Lock on BSC → Mint on Polygon ────────────────────────────────────────

    function test_fullFlow_lockAndMint() public {
        vm.prank(aliceBscSafe);
        predictionMarketToken.setApprovalForAll(address(escrow), true);

        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 2000, alice, _option);

        // BSC state after lock
        assertEq(predictionMarketToken.balanceOf(aliceBscSafe, TOKEN_ID_YES), 3000); // 5000 - 2000
        assertEq(predictionMarketToken.balanceOf(address(escrow), TOKEN_ID_YES), 2000);
        assertEq(escrow.totalLocked(TOKEN_ID_YES), 2000);

        bscEndpoint.deliverMessage(0, polyEndpoint);

        // Polygon state after delivery
        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_YES), 2000);
        assertEq(wrappedToken.totalSupply(TOKEN_ID_YES), 2000);
        assertEq(receiver.totalBridged(TOKEN_ID_YES), 2000);
    }

    // ─── Lock → Mint → Bridge Back → Unlock ───────────────────────────────────

    function test_fullFlow_roundTrip() public {
        // Phase 1: BSC → Polygon
        // Started with 5000. Lock 1000 → aliceBscSafe has 4000, escrow has 1000
        vm.prank(aliceBscSafe);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 1000, alice, _option);
        bscEndpoint.deliverMessage(0, polyEndpoint);

        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_YES), 1000);

        // Phase 2: Polygon → BSC
        // Bridge back 600 → alice has 400 wrapped remaining, aliceBscSafe gets 600 back
        vm.prank(alice);
        receiver.bridgeBack{value: 0.01 ether}(TOKEN_ID_YES, 600, aliceBscSafe, _option);

        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_YES), 400);
        assertEq(wrappedToken.totalSupply(TOKEN_ID_YES), 400);

        polyEndpoint.deliverMessage(0, bscEndpoint);

        // aliceBscSafe: 4000 + 600 = 4600. Escrow retains 400.
        assertEq(predictionMarketToken.balanceOf(aliceBscSafe, TOKEN_ID_YES), 4600);
        assertEq(predictionMarketToken.balanceOf(address(escrow), TOKEN_ID_YES), 400);
        assertEq(escrow.totalLocked(TOKEN_ID_YES), 400);
    }

    // ─── Complete round trip ───────────────────────────────────────────────────

    function test_fullFlow_completeRoundTrip() public {
        vm.prank(aliceBscSafe);
        predictionMarketToken.setApprovalForAll(address(escrow), true);

        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 1000, alice, _option);
        bscEndpoint.deliverMessage(0, polyEndpoint);

        vm.prank(alice);
        receiver.bridgeBack{value: 0.01 ether}(TOKEN_ID_YES, 1000, aliceBscSafe, _option);
        polyEndpoint.deliverMessage(0, bscEndpoint);

        // All state back to original
        assertEq(predictionMarketToken.balanceOf(aliceBscSafe, TOKEN_ID_YES), 5000);
        assertEq(predictionMarketToken.balanceOf(address(escrow), TOKEN_ID_YES), 0);
        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_YES), 0);
        assertEq(wrappedToken.totalSupply(TOKEN_ID_YES), 0);
        assertEq(escrow.totalLocked(TOKEN_ID_YES), 0);
        assertEq(receiver.totalBridged(TOKEN_ID_YES), 0);
    }

    // ─── Multiple token types ─────────────────────────────────────────────────

    function test_fullFlow_multipleTokenTypes() public {
        vm.prank(aliceBscSafe);
        predictionMarketToken.setApprovalForAll(address(escrow), true);

        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 2000, alice, _option);
        bscEndpoint.deliverMessage(0, polyEndpoint);

        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_NO, 1500, alice, _option);
        bscEndpoint.deliverMessage(1, polyEndpoint);

        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_YES), 2000);
        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_NO), 1500);
        assertEq(wrappedToken.totalSupply(TOKEN_ID_YES), 2000);
        assertEq(wrappedToken.totalSupply(TOKEN_ID_NO), 1500);
        assertEq(escrow.totalLocked(TOKEN_ID_YES), 2000);
        assertEq(escrow.totalLocked(TOKEN_ID_NO), 1500);
    }

    // ─── Multiple users ───────────────────────────────────────────────────────

    function test_fullFlow_multipleUsers() public {
        address bob        = makeAddr("bob");
        address bobBscSafe = makeAddr("bobBscSafe");
        predictionMarketToken.mint(bobBscSafe, TOKEN_ID_YES, 3000);
        vm.deal(bobBscSafe, 10 ether);
        vm.deal(bob, 10 ether);

        vm.prank(aliceBscSafe);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        vm.prank(bobBscSafe);
        predictionMarketToken.setApprovalForAll(address(escrow), true);

        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 1000, alice, _option);
        bscEndpoint.deliverMessage(0, polyEndpoint);

        vm.prank(bobBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 2000, bob, _option);
        bscEndpoint.deliverMessage(1, polyEndpoint);

        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_YES), 1000);
        assertEq(wrappedToken.balanceOf(bob, TOKEN_ID_YES), 2000);
        assertEq(wrappedToken.totalSupply(TOKEN_ID_YES), 3000);
        assertEq(predictionMarketToken.balanceOf(address(escrow), TOKEN_ID_YES), 3000);
    }

    // ─── Bridge back to different BSC address ─────────────────────────────────

    function test_bridgeBack_toDifferentAddress() public {
        vm.prank(aliceBscSafe);
        predictionMarketToken.setApprovalForAll(address(escrow), true);

        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 1000, alice, _option);
        bscEndpoint.deliverMessage(0, polyEndpoint);

        address alternateRecipient = makeAddr("alternate");

        vm.prank(alice);
        receiver.bridgeBack{value: 0.01 ether}(TOKEN_ID_YES, 1000, alternateRecipient, _option);
        polyEndpoint.deliverMessage(0, bscEndpoint);

        assertEq(predictionMarketToken.balanceOf(alternateRecipient, TOKEN_ID_YES), 1000);
        assertEq(predictionMarketToken.balanceOf(aliceBscSafe, TOKEN_ID_YES), 4000);
    }
}