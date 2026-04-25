// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BridgeReceiver} from "../src/BridgeReceiver.sol";
import {WrappedPredictionToken} from "../src/WrappedPredictionToken.sol";
import {MockEndpointV2} from "./mocks/MockEndpointV2.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract BridgeReceiverTest is Test {
    BridgeReceiver public receiver;
    WrappedPredictionToken public wrappedToken;
    MockEndpointV2 public polyEndpoint;
    bytes32 public escrowPeer;

    address public owner         = makeAddr("owner");
    address public user          = makeAddr("user");
    address public predictionMarketEscrow = makeAddr("predictionMarketEscrow");
    address public predictionMarketContract = makeAddr("predictionMarketContract");

    uint32 constant BSC_EID         = 30102;
    uint32 constant POLYGON_EID     = 30109;
    uint256 constant PREDICTION_TOKEN_ID = 42;

    bytes public _option = abi.encodePacked(
        uint16(0x0003),
        uint8(0x01),
        uint16(0x0011),
        uint8(0x01),
        uint128(400_000)  // matches enforced floor
    );

    function setUp() public {
        polyEndpoint = new MockEndpointV2(POLYGON_EID);

        vm.startPrank(owner);
        wrappedToken = new WrappedPredictionToken(owner, predictionMarketContract);
        receiver     = new BridgeReceiver(address(polyEndpoint), owner, address(wrappedToken), BSC_EID);
        escrowPeer   = bytes32(uint256(uint160(predictionMarketEscrow)));

        wrappedToken.setBridge(address(receiver));
        receiver.setPeer(BSC_EID, escrowPeer);
        receiver.setDstGasLimit(400_000);
        receiver.unpause();
        vm.stopPrank();

        vm.deal(user, 10 ether);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    /// @dev Simulate a bridge-in LZ message, minting wrapped tokens to _to.
    function _mintWrappedTokens(address _to, uint256 _amount) internal {
        bytes memory payload = abi.encode(_to, PREDICTION_TOKEN_ID, _amount);
        vm.prank(address(polyEndpoint));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );
    }

    // ─── Receive Lock (mint) ──────────────────────────────────────────────────

    function test_lzReceive_mintsWrappedTokens() public {
        bytes memory payload = abi.encode(user, PREDICTION_TOKEN_ID, uint256(1000));

        vm.prank(address(polyEndpoint));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );

        assertEq(wrappedToken.balanceOf(user, PREDICTION_TOKEN_ID), 1000);
        assertEq(receiver.totalBridged(PREDICTION_TOKEN_ID), 1000);
    }

    function test_lzReceive_multipleMintsAccumulate() public {
        bytes memory payload1 = abi.encode(user, PREDICTION_TOKEN_ID, uint256(500));
        bytes memory payload2 = abi.encode(user, PREDICTION_TOKEN_ID, uint256(300));

        vm.startPrank(address(polyEndpoint));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid1"),
            payload1,
            address(0),
            ""
        );
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 2}),
            keccak256("guid2"),
            payload2,
            address(0),
            ""
        );
        vm.stopPrank();

        assertEq(wrappedToken.balanceOf(user, PREDICTION_TOKEN_ID), 800);
        assertEq(receiver.totalBridged(PREDICTION_TOKEN_ID), 800);
    }

    function test_lzReceive_differentRecipients() public {
        address alice = makeAddr("alice");
        address bob   = makeAddr("bob");

        vm.startPrank(address(polyEndpoint));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid1"),
            abi.encode(alice, PREDICTION_TOKEN_ID, uint256(600)),
            address(0),
            ""
        );
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 2}),
            keccak256("guid2"),
            abi.encode(bob, PREDICTION_TOKEN_ID, uint256(400)),
            address(0),
            ""
        );
        vm.stopPrank();

        assertEq(wrappedToken.balanceOf(alice, PREDICTION_TOKEN_ID), 600);
        assertEq(wrappedToken.balanceOf(bob, PREDICTION_TOKEN_ID), 400);
        assertEq(receiver.totalBridged(PREDICTION_TOKEN_ID), 1000);
    }

    function test_lzReceive_revertNotEndpoint() public {
        bytes memory payload = abi.encode(user, PREDICTION_TOKEN_ID, uint256(100));

        vm.prank(user); // not the endpoint
        vm.expectRevert(abi.encodeWithSignature("OnlyEndpoint(address)", user));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );
    }

    function test_lzReceive_revertNotPeer() public {
        // Mint first so _lzReceive body is reachable — peer check fires before body
        // but we need valid state to confirm it's peer that's rejecting, not something else
        bytes memory payload = abi.encode(user, PREDICTION_TOKEN_ID, uint256(100));
        bytes32 fakePeer = bytes32(uint256(uint160(makeAddr("fakeSender"))));

        vm.prank(address(polyEndpoint));
        vm.expectRevert(); // OnlyPeer
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: fakePeer, nonce: 1}), // ← untrusted sender
            keccak256("guid"),
            payload,
            address(0),
            ""
        );
    }

    function test_lzReceive_succeedsWhenPaused() public {
        // _lzReceive is intentionally not gated by pause —
        // in-flight BSC → Polygon messages must always land
        vm.prank(owner);
        receiver.pause();

        bytes memory payload = abi.encode(user, PREDICTION_TOKEN_ID, uint256(1000));
        vm.prank(address(polyEndpoint));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );

        assertEq(wrappedToken.balanceOf(user, PREDICTION_TOKEN_ID), 1000);
        assertEq(receiver.totalBridged(PREDICTION_TOKEN_ID), 1000);
    }

    // ─── Bridge Back (burn + send unlock) ─────────────────────────────────────

    function test_bridgeBack_success() public {
        _mintWrappedTokens(user, 1000);

        address bscRecipient = makeAddr("bscSafe");

        vm.prank(user);
        receiver.bridgeBack{value: 0.01 ether}(PREDICTION_TOKEN_ID, 400, bscRecipient, _option);

        assertEq(wrappedToken.balanceOf(user, PREDICTION_TOKEN_ID), 600);
        assertEq(receiver.totalBridged(PREDICTION_TOKEN_ID), 600);
        assertEq(polyEndpoint.messageCount(), 1);
    }

    function test_bridgeBack_messagePayload() public {
        _mintWrappedTokens(user, 1000);

        address bscRecipient = makeAddr("bscSafe");

        vm.prank(user);
        receiver.bridgeBack{value: 0.01 ether}(PREDICTION_TOKEN_ID, 500, bscRecipient, _option);

        MockEndpointV2.StoredMessage memory msg_ = polyEndpoint.lastMessage();
        assertEq(msg_.dstEid, BSC_EID);

        (address recipient, uint256 tokenId, uint256 amount) =
            abi.decode(msg_.message, (address, uint256, uint256));
        assertEq(recipient, bscRecipient);
        assertEq(tokenId, PREDICTION_TOKEN_ID);
        assertEq(amount, 500);
    }

    function test_bridgeBack_revertZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(BridgeReceiver.ZeroAmount.selector);
        receiver.bridgeBack{value: 0.01 ether}(PREDICTION_TOKEN_ID, 0, makeAddr("bsc"), _option);
    }

    function test_bridgeBack_revertZeroAddress() public {
        vm.prank(user);
        vm.expectRevert(BridgeReceiver.ZeroAddress.selector);
        receiver.bridgeBack{value: 0.01 ether}(PREDICTION_TOKEN_ID, 100, address(0), _option);
    }

    function test_bridgeBack_revertInsufficientBridged() public {
        // totalBridged[id]=100, requesting 200 → InsufficientBridgedBalance fires
        // before ERC1155 burn is ever reached
        _mintWrappedTokens(user, 100);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(
            BridgeReceiver.InsufficientBridgedBalance.selector,
            PREDICTION_TOKEN_ID,
            uint256(100), // totalBridged
            uint256(200)  // requested
        ));
        receiver.bridgeBack{value: 0.01 ether}(PREDICTION_TOKEN_ID, 200, makeAddr("bsc"), _option);
    }

    function test_bridgeBack_revertWhenPaused() public {
        _mintWrappedTokens(user, 1000);

        vm.prank(owner);
        receiver.pause();

        vm.prank(user);
        vm.expectRevert();
        receiver.bridgeBack{value: 0.01 ether}(PREDICTION_TOKEN_ID, 100, makeAddr("bsc"), _option);
    }

    // ─── Config ───────────────────────────────────────────────────────────────

    function test_setDstGasLimit() public {
        vm.prank(owner);
        receiver.setDstGasLimit(500_000);
        assertEq(receiver.dstGasLimit(), 500_000);
    }

    function test_setDstGasLimit_revertNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        receiver.setDstGasLimit(500_000);
    }
}