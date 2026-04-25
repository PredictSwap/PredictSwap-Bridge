// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PredictionMarketEscrow} from "../src/PredictionMarketEscrow.sol";
import {MockEndpointV2} from "./mocks/MockEndpointV2.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract PredictionMarketEscrowTest is Test {
    PredictionMarketEscrow public escrow;
    MockEndpointV2 public bscEndpoint;
    MockERC1155 public predictionMarketToken;

    address public owner           = makeAddr("owner");
    address public user            = makeAddr("user");
    address public polygonRecipient = makeAddr("polygonRecipient");
    address public bridgeReceiver  = makeAddr("bridgeReceiver");

    bytes public _option = abi.encodePacked(
        uint16(0x0003),
        uint8(0x01),
        uint16(0x0011),
        uint8(0x01),
        uint128(400_000)
    );

    uint32 constant BSC_EID     = 30102;
    uint32 constant POLYGON_EID = 30109;
    uint256 constant TOKEN_ID   = 1;

    bytes32 bridgeReceiverPeer;

    function setUp() public {
        bscEndpoint  = new MockEndpointV2(BSC_EID);
        predictionMarketToken = new MockERC1155();

        vm.startPrank(owner);
        escrow = new PredictionMarketEscrow(address(bscEndpoint), owner, address(predictionMarketToken), POLYGON_EID);
        bridgeReceiverPeer = bytes32(uint256(uint160(bridgeReceiver)));
        escrow.setPeer(POLYGON_EID, bridgeReceiverPeer);
        escrow.setDstGasLimit(400_000);
        escrow.unpause();
        vm.stopPrank();

        predictionMarketToken.mint(user, TOKEN_ID, 10_000);
        vm.deal(user, 10 ether);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    /// @dev Lock tokens from user as a setup step for unlock tests.
    function _lockTokens(uint256 amount) internal {
        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, amount, polygonRecipient, _option);
        vm.stopPrank();
    }

    // ─── Lock ─────────────────────────────────────────────────────────────────

    function test_lock_success() public {
        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 1000, polygonRecipient, _option);
        vm.stopPrank();

        assertEq(predictionMarketToken.balanceOf(address(escrow), TOKEN_ID), 1000);
        assertEq(predictionMarketToken.balanceOf(user, TOKEN_ID), 9000);
        assertEq(escrow.totalLocked(TOKEN_ID), 1000);
        assertEq(bscEndpoint.messageCount(), 1);
    }

    function test_lock_messagePayload() public {
        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 500, polygonRecipient, _option);
        vm.stopPrank();

        MockEndpointV2.StoredMessage memory msg_ = bscEndpoint.lastMessage();
        assertEq(msg_.dstEid, POLYGON_EID);
        assertEq(msg_.sender, address(escrow));

        (address recipient, uint256 tokenId, uint256 amount) =
            abi.decode(msg_.message, (address, uint256, uint256));
        assertEq(recipient, polygonRecipient);
        assertEq(tokenId, TOKEN_ID);
        assertEq(amount, 500);
    }

    function test_lock_multipleLocks() public {
        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 300, polygonRecipient, _option);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 700, polygonRecipient, _option);
        vm.stopPrank();

        assertEq(escrow.totalLocked(TOKEN_ID), 1000);
        assertEq(bscEndpoint.messageCount(), 2);
    }

    function test_lock_revertZeroAmount() public {
        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        vm.expectRevert(PredictionMarketEscrow.ZeroAmount.selector);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 0, polygonRecipient, _option);
        vm.stopPrank();
    }

    function test_lock_revertZeroAddress() public {
        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        vm.expectRevert(PredictionMarketEscrow.ZeroAddress.selector);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 100, address(0), _option);
        vm.stopPrank();
    }

    function test_lock_revertNoApproval() public {
        vm.prank(user);
        vm.expectRevert();
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 100, polygonRecipient, _option);
    }

    function test_lock_revertInsufficientBalance() public {
        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        vm.expectRevert();
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 99_999, polygonRecipient, _option);
        vm.stopPrank();
    }

    function test_lock_revertWhenPaused() public {
        vm.prank(owner);
        escrow.pause();

        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        vm.expectRevert();
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 100, polygonRecipient, _option);
        vm.stopPrank();
    }

    // ─── Unlock (via LZ receive) ───────────────────────────────────────────────

    function test_unlock_success() public {
        _lockTokens(1000);

        bytes memory payload = abi.encode(user, TOKEN_ID, uint256(600));
        vm.prank(address(bscEndpoint));
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: bridgeReceiverPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );

        assertEq(predictionMarketToken.balanceOf(user, TOKEN_ID), 9600); // 9000 + 600
        assertEq(predictionMarketToken.balanceOf(address(escrow), TOKEN_ID), 400);
        assertEq(escrow.totalLocked(TOKEN_ID), 400);
    }

    function test_unlock_toDifferentAddress() public {
        _lockTokens(1000);

        address bscRecipient = makeAddr("bscRecipient");
        bytes memory payload = abi.encode(bscRecipient, TOKEN_ID, uint256(1000));

        vm.prank(address(bscEndpoint));
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: bridgeReceiverPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );

        assertEq(predictionMarketToken.balanceOf(bscRecipient, TOKEN_ID), 1000);
        assertEq(predictionMarketToken.balanceOf(user, TOKEN_ID), 9000); // unchanged
    }

    function test_unlock_revertInsufficientLocked() public {
        // Lock 500, try to unlock 1000
        _lockTokens(500);

        bytes memory payload = abi.encode(user, TOKEN_ID, uint256(1000));

        vm.prank(address(bscEndpoint));
        vm.expectRevert(abi.encodeWithSelector(
            PredictionMarketEscrow.InsufficientLockedBalance.selector,
            TOKEN_ID,
            uint256(500),
            uint256(1000)
        ));
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: bridgeReceiverPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );
    }

    function test_unlock_revertNotEndpoint() public {
        bytes memory payload = abi.encode(user, TOKEN_ID, uint256(100));

        vm.prank(user); // not the endpoint
        vm.expectRevert(abi.encodeWithSignature("OnlyEndpoint(address)", user));
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: bridgeReceiverPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );
    }

    function test_unlock_revertNotPeer() public {
        // Lock first so InsufficientLockedBalance doesn't fire before peer check
        _lockTokens(1000);

        bytes memory payload = abi.encode(user, TOKEN_ID, uint256(100));
        bytes32 fakePeer = bytes32(uint256(uint160(makeAddr("fakeSender"))));

        vm.prank(address(bscEndpoint));
        vm.expectRevert(); // OnlyPeer
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: fakePeer, nonce: 1}), // ← untrusted sender
            keccak256("guid"),
            payload,
            address(0),
            ""
        );
    }

    // ─── Pause ────────────────────────────────────────────────────────────────

    function test_unlock_succeedsWhenPaused() public {
        // _lzReceive is intentionally not gated by pause —
        // users must always be able to retrieve their tokens
        _lockTokens(1000);

        vm.prank(owner);
        escrow.pause();

        bytes memory payload = abi.encode(user, TOKEN_ID, uint256(1000));
        vm.prank(address(bscEndpoint));
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: bridgeReceiverPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );

        assertEq(predictionMarketToken.balanceOf(user, TOKEN_ID), 10_000);
    }

    // ─── Config ───────────────────────────────────────────────────────────────

    function test_setDstGasLimit() public {
        vm.prank(owner);
        escrow.setDstGasLimit(500_000);
        assertEq(escrow.dstGasLimit(), 500_000);
    }

    function test_setDstGasLimit_revertNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        escrow.setDstGasLimit(500_000);
    }

    // ─── ERC1155 Receiver ─────────────────────────────────────────────────────

    function test_supportsInterface() public view {
        assertTrue(escrow.supportsInterface(0x4e2312e0)); // IERC1155Receiver
        assertTrue(escrow.supportsInterface(0x01ffc9a7)); // IERC165
    }
}