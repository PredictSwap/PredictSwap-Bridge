// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PredictionMarketEscrow} from "../src/PredictionMarketEscrow.sol";
import {BridgeReceiver} from "../src/BridgeReceiver.sol";
import {WrappedPredictionToken} from "../src/WrappedPredictionToken.sol";
import {MockEndpointV2} from "./mocks/MockEndpointV2.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

// ══════════════════════════════════════════════════════════════════════════════
//  WrappedPredictionToken Fuzz Tests
// ══════════════════════════════════════════════════════════════════════════════

contract WrappedPredictionTokenFuzzTest is Test {
    WrappedPredictionToken public wrappedToken;

    address public owner = makeAddr("owner");
    address public bridge = makeAddr("bridge");
    address public predictionMarketContract = makeAddr("predictionMarketContract");

    function setUp() public {
        vm.startPrank(owner);
        wrappedToken = new WrappedPredictionToken(owner, predictionMarketContract);
        wrappedToken.setBridge(bridge);
        vm.stopPrank();
    }

    function testFuzz_mint_updatesBalanceAndSupply(
        address to,
        uint256 tokenId,
        uint256 amount
    ) public {
        vm.assume(to != address(0));
        vm.assume(amount > 0 && amount < type(uint128).max);
        vm.assume(to.code.length == 0);

        vm.prank(bridge);
        wrappedToken.mint(to, tokenId, amount);

        assertEq(wrappedToken.balanceOf(to, tokenId), amount);
        assertEq(wrappedToken.totalSupply(tokenId), amount);
    }

    function testFuzz_mintThenBurn_fullAmount(
        address to,
        uint256 tokenId,
        uint256 amount
    ) public {
        vm.assume(to != address(0));
        vm.assume(amount > 0 && amount < type(uint128).max);
        vm.assume(to.code.length == 0);

        vm.startPrank(bridge);
        wrappedToken.mint(to, tokenId, amount);
        wrappedToken.burn(to, tokenId, amount);
        vm.stopPrank();

        assertEq(wrappedToken.balanceOf(to, tokenId), 0);
        assertEq(wrappedToken.totalSupply(tokenId), 0);
    }

    function testFuzz_mintThenBurn_partialAmount(
        address to,
        uint256 tokenId,
        uint256 mintAmount,
        uint256 burnAmount
    ) public {
        vm.assume(to != address(0));
        vm.assume(to.code.length == 0);
        vm.assume(mintAmount > 0 && mintAmount < type(uint128).max);
        vm.assume(burnAmount > 0 && burnAmount <= mintAmount);

        vm.startPrank(bridge);
        wrappedToken.mint(to, tokenId, mintAmount);
        wrappedToken.burn(to, tokenId, burnAmount);
        vm.stopPrank();

        assertEq(wrappedToken.balanceOf(to, tokenId), mintAmount - burnAmount);
        assertEq(wrappedToken.totalSupply(tokenId), mintAmount - burnAmount);
    }

    function testFuzz_mint_revertNonBridge(
        address caller,
        uint256 tokenId,
        uint256 amount
    ) public {
        vm.assume(caller != bridge);
        vm.assume(amount > 0);

        vm.prank(caller);
        vm.expectRevert(WrappedPredictionToken.OnlyBridge.selector);
        wrappedToken.mint(caller, tokenId, amount);
    }

    function testFuzz_burn_revertNonBridge(
        address caller,
        uint256 tokenId,
        uint256 amount
    ) public {
        vm.assume(caller != bridge);
        vm.assume(amount > 0);

        vm.prank(caller);
        vm.expectRevert(WrappedPredictionToken.OnlyBridge.selector);
        wrappedToken.burn(caller, tokenId, amount);
    }

    function testFuzz_mint_revertZeroAddress(uint256 tokenId, uint256 amount) public {
        vm.assume(amount > 0);

        vm.prank(bridge);
        vm.expectRevert(WrappedPredictionToken.ZeroAddress.selector);
        wrappedToken.mint(address(0), tokenId, amount);
    }

    function testFuzz_mint_revertZeroAmount(address to, uint256 tokenId) public {
        vm.assume(to != address(0));

        vm.prank(bridge);
        vm.expectRevert(WrappedPredictionToken.ZeroAmount.selector);
        wrappedToken.mint(to, tokenId, 0);
    }

    function testFuzz_burn_revertZeroAmount(address from, uint256 tokenId) public {
        vm.prank(bridge);
        vm.expectRevert(WrappedPredictionToken.ZeroAmount.selector);
        wrappedToken.burn(from, tokenId, 0);
    }

    function testFuzz_multipleMints_supplyAccumulates(
        address to,
        uint256 tokenId,
        uint128 amount1,
        uint128 amount2
    ) public {
        vm.assume(to != address(0));
        vm.assume(amount1 > 0 && amount2 > 0);
        vm.assume(to.code.length == 0);

        vm.startPrank(bridge);
        wrappedToken.mint(to, tokenId, amount1);
        wrappedToken.mint(to, tokenId, amount2);
        vm.stopPrank();

        uint256 total = uint256(amount1) + uint256(amount2);
        assertEq(wrappedToken.balanceOf(to, tokenId), total);
        assertEq(wrappedToken.totalSupply(tokenId), total);
    }

    function testFuzz_mintToMultipleRecipients_supplyIsSumOfAll(
        uint256 tokenId,
        uint128 amount1,
        uint128 amount2
    ) public {
        vm.assume(amount1 > 0 && amount2 > 0);

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        vm.startPrank(bridge);
        wrappedToken.mint(alice, tokenId, amount1);
        wrappedToken.mint(bob, tokenId, amount2);
        vm.stopPrank();

        uint256 total = uint256(amount1) + uint256(amount2);
        assertEq(wrappedToken.totalSupply(tokenId), total);
        assertEq(wrappedToken.balanceOf(alice, tokenId), amount1);
        assertEq(wrappedToken.balanceOf(bob, tokenId), amount2);
    }

    function testFuzz_setBridge_revertIfAlreadySet(address newBridge) public {
        vm.assume(newBridge != address(0));

        vm.prank(owner);
        vm.expectRevert(WrappedPredictionToken.BridgeAlreadySet.selector);
        wrappedToken.setBridge(newBridge);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BridgeReceiver Fuzz Tests
// ══════════════════════════════════════════════════════════════════════════════

contract BridgeReceiverFuzzTest is Test {
    BridgeReceiver public receiver;
    WrappedPredictionToken public wrappedToken;
    MockEndpointV2 public polyEndpoint;
    bytes32 public escrowPeer;

    address public owner = makeAddr("owner");
    address public predictionMarketEscrow = makeAddr("predictionMarketEscrow");
    address public predictionMarketContract = makeAddr("predictionMarketContract");

    uint32 constant BSC_EID = 30102;
    uint32 constant POLYGON_EID = 30109;

    bytes public _option = abi.encodePacked(
        uint16(0x0003), uint8(0x01), uint16(0x0011), uint8(0x01), uint128(400_000)
    );

    function setUp() public {
        polyEndpoint = new MockEndpointV2(POLYGON_EID);

        vm.startPrank(owner);
        wrappedToken = new WrappedPredictionToken(owner, predictionMarketContract);
        receiver = new BridgeReceiver(address(polyEndpoint), owner, address(wrappedToken), BSC_EID);
        escrowPeer = bytes32(uint256(uint160(predictionMarketEscrow)));

        wrappedToken.setBridge(address(receiver));
        receiver.setPeer(BSC_EID, escrowPeer);
        receiver.setDstGasLimit(400_000);
        receiver.unpause();
        vm.stopPrank();
    }

    function _bridgeIn(address to, uint256 tokenId, uint256 amount) internal {
        bytes memory payload = abi.encode(to, tokenId, amount);
        vm.prank(address(polyEndpoint));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );
    }

    function testFuzz_lzReceive_mintsCorrectly(
        address recipient,
        uint256 tokenId,
        uint256 amount
    ) public {
        vm.assume(recipient != address(0));
        vm.assume(amount > 0 && amount < type(uint128).max);
        vm.assume(recipient.code.length == 0);

        _bridgeIn(recipient, tokenId, amount);

        assertEq(wrappedToken.balanceOf(recipient, tokenId), amount);
        assertEq(wrappedToken.totalSupply(tokenId), amount);
        assertEq(receiver.totalBridged(tokenId), amount);
    }

    function testFuzz_lzReceive_invariant_totalBridgedEqualsSupply(
        uint256 tokenId,
        uint128 amount1,
        uint128 amount2
    ) public {
        vm.assume(amount1 > 0 && amount2 > 0);

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        bytes memory payload1 = abi.encode(alice, tokenId, uint256(amount1));
        bytes memory payload2 = abi.encode(bob, tokenId, uint256(amount2));

        vm.startPrank(address(polyEndpoint));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid1"), payload1, address(0), ""
        );
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 2}),
            keccak256("guid2"), payload2, address(0), ""
        );
        vm.stopPrank();

        assertEq(receiver.totalBridged(tokenId), wrappedToken.totalSupply(tokenId));
    }

    function testFuzz_bridgeBack_success(
        uint256 tokenId,
        uint128 mintAmount,
        uint128 burnAmount
    ) public {
        vm.assume(mintAmount > 0);
        vm.assume(burnAmount > 0 && burnAmount <= mintAmount);

        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        _bridgeIn(user, tokenId, mintAmount);

        vm.prank(user);
        receiver.bridgeBack{value: 0.01 ether}(tokenId, burnAmount, makeAddr("bsc"), _option);

        uint256 remaining = uint256(mintAmount) - uint256(burnAmount);
        assertEq(wrappedToken.balanceOf(user, tokenId), remaining);
        assertEq(receiver.totalBridged(tokenId), remaining);
        assertEq(wrappedToken.totalSupply(tokenId), remaining);
    }

    function testFuzz_bridgeBack_invariant_afterPartialBurn(
        uint256 tokenId,
        uint128 mintAmount,
        uint128 burnAmount
    ) public {
        vm.assume(mintAmount > 0);
        vm.assume(burnAmount > 0 && burnAmount <= mintAmount);

        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        _bridgeIn(user, tokenId, mintAmount);

        vm.prank(user);
        receiver.bridgeBack{value: 0.01 ether}(tokenId, burnAmount, makeAddr("bsc"), _option);

        assertEq(receiver.totalBridged(tokenId), wrappedToken.totalSupply(tokenId));
    }

    function testFuzz_bridgeBack_revertExceedsBridged(
        uint256 tokenId,
        uint128 mintAmount,
        uint128 extraAmount
    ) public {
        vm.assume(mintAmount > 0 && mintAmount < type(uint128).max);
        vm.assume(extraAmount > 0);
        uint256 requested = uint256(mintAmount) + uint256(extraAmount);

        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        _bridgeIn(user, tokenId, mintAmount);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(
            BridgeReceiver.InsufficientBridgedBalance.selector,
            tokenId, uint256(mintAmount), requested
        ));
        receiver.bridgeBack{value: 0.01 ether}(tokenId, requested, makeAddr("bsc"), _option);
    }

    function testFuzz_bridgeBack_revertZeroAmount(uint256 tokenId) public {
        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        vm.prank(user);
        vm.expectRevert(BridgeReceiver.ZeroAmount.selector);
        receiver.bridgeBack{value: 0.01 ether}(tokenId, 0, makeAddr("bsc"), _option);
    }

    function testFuzz_bridgeBack_revertZeroRecipient(uint256 tokenId, uint128 amount) public {
        vm.assume(amount > 0);
        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        _bridgeIn(user, tokenId, amount);

        vm.prank(user);
        vm.expectRevert(BridgeReceiver.ZeroAddress.selector);
        receiver.bridgeBack{value: 0.01 ether}(tokenId, amount, address(0), _option);
    }

    function testFuzz_lzReceive_worksWhenPaused(
        address recipient,
        uint256 tokenId,
        uint256 amount
    ) public {
        vm.assume(recipient != address(0));
        vm.assume(amount > 0 && amount < type(uint128).max);
        vm.assume(recipient.code.length == 0);

        vm.prank(owner);
        receiver.pause();

        _bridgeIn(recipient, tokenId, amount);

        assertEq(wrappedToken.balanceOf(recipient, tokenId), amount);
        assertEq(receiver.totalBridged(tokenId), amount);
    }

    function testFuzz_setDstGasLimit(uint128 gasLimit) public {
        vm.prank(owner);
        receiver.setDstGasLimit(gasLimit);
        assertEq(receiver.dstGasLimit(), gasLimit);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  PredictionMarketEscrow Fuzz Tests
// ══════════════════════════════════════════════════════════════════════════════

contract PredictionMarketEscrowFuzzTest is Test {
    PredictionMarketEscrow public escrow;
    MockEndpointV2 public bscEndpoint;
    MockERC1155 public predictionMarketToken;

    address public owner = makeAddr("owner");
    address public bridgeReceiver = makeAddr("bridgeReceiver");
    bytes32 bridgeReceiverPeer;

    uint32 constant BSC_EID = 30102;
    uint32 constant POLYGON_EID = 30109;

    bytes public _option = abi.encodePacked(
        uint16(0x0003), uint8(0x01), uint16(0x0011), uint8(0x01), uint128(400_000)
    );

    function setUp() public {
        bscEndpoint = new MockEndpointV2(BSC_EID);
        predictionMarketToken = new MockERC1155();

        vm.startPrank(owner);
        escrow = new PredictionMarketEscrow(address(bscEndpoint), owner, address(predictionMarketToken), POLYGON_EID);
        bridgeReceiverPeer = bytes32(uint256(uint160(bridgeReceiver)));
        escrow.setPeer(POLYGON_EID, bridgeReceiverPeer);
        escrow.setDstGasLimit(400_000);
        escrow.unpause();
        vm.stopPrank();
    }

    function testFuzz_lock_success(
        uint256 tokenId,
        uint128 amount,
        address polygonRecipient
    ) public {
        vm.assume(polygonRecipient != address(0));
        vm.assume(amount > 0);

        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        predictionMarketToken.mint(user, tokenId, amount);

        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(tokenId, amount, polygonRecipient, _option);
        vm.stopPrank();

        assertEq(predictionMarketToken.balanceOf(address(escrow), tokenId), amount);
        assertEq(predictionMarketToken.balanceOf(user, tokenId), 0);
        assertEq(escrow.totalLocked(tokenId), amount);
    }

    function testFuzz_lock_multipleLocks_accumulate(
        uint256 tokenId,
        uint128 amount1,
        uint128 amount2
    ) public {
        vm.assume(amount1 > 0 && amount2 > 0);

        address user = makeAddr("user");
        vm.deal(user, 10 ether);
        address polygonRecipient = makeAddr("polygonRecipient");

        uint256 total = uint256(amount1) + uint256(amount2);
        predictionMarketToken.mint(user, tokenId, total);

        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(tokenId, amount1, polygonRecipient, _option);
        escrow.lock{value: 0.01 ether}(tokenId, amount2, polygonRecipient, _option);
        vm.stopPrank();

        assertEq(escrow.totalLocked(tokenId), total);
        assertEq(predictionMarketToken.balanceOf(address(escrow), tokenId), total);
    }

    function testFuzz_lock_revertZeroAmount(uint256 tokenId, address recipient) public {
        vm.assume(recipient != address(0));
        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        vm.expectRevert(PredictionMarketEscrow.ZeroAmount.selector);
        escrow.lock{value: 0.01 ether}(tokenId, 0, recipient, _option);
        vm.stopPrank();
    }

    function testFuzz_lock_revertZeroRecipient(uint256 tokenId, uint128 amount) public {
        vm.assume(amount > 0);
        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        predictionMarketToken.mint(user, tokenId, amount);

        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        vm.expectRevert(PredictionMarketEscrow.ZeroAddress.selector);
        escrow.lock{value: 0.01 ether}(tokenId, amount, address(0), _option);
        vm.stopPrank();
    }

    function testFuzz_lock_revertWhenPaused(uint256 tokenId, uint128 amount) public {
        vm.assume(amount > 0);

        address user = makeAddr("user");
        vm.deal(user, 10 ether);
        predictionMarketToken.mint(user, tokenId, amount);

        vm.prank(owner);
        escrow.pause();

        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        vm.expectRevert();
        escrow.lock{value: 0.01 ether}(tokenId, amount, makeAddr("poly"), _option);
        vm.stopPrank();
    }

    function testFuzz_unlock_success(
        uint256 tokenId,
        uint128 lockAmount,
        uint128 unlockAmount
    ) public {
        vm.assume(lockAmount > 0);
        vm.assume(unlockAmount > 0 && unlockAmount <= lockAmount);

        address user = makeAddr("user");
        vm.deal(user, 10 ether);
        address bscRecipient = makeAddr("bscRecipient");

        predictionMarketToken.mint(user, tokenId, lockAmount);

        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(tokenId, lockAmount, makeAddr("poly"), _option);
        vm.stopPrank();

        bytes memory payload = abi.encode(bscRecipient, tokenId, uint256(unlockAmount));
        vm.prank(address(bscEndpoint));
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: bridgeReceiverPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );

        uint256 remaining = uint256(lockAmount) - uint256(unlockAmount);
        assertEq(escrow.totalLocked(tokenId), remaining);
        assertEq(predictionMarketToken.balanceOf(bscRecipient, tokenId), unlockAmount);
        assertEq(predictionMarketToken.balanceOf(address(escrow), tokenId), remaining);
    }

    function testFuzz_unlock_revertExceedsLocked(
        uint256 tokenId,
        uint128 lockAmount,
        uint128 extraAmount
    ) public {
        vm.assume(lockAmount > 0 && lockAmount < type(uint128).max);
        vm.assume(extraAmount > 0);
        uint256 unlockAmount = uint256(lockAmount) + uint256(extraAmount);

        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        predictionMarketToken.mint(user, tokenId, lockAmount);

        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(tokenId, lockAmount, makeAddr("poly"), _option);
        vm.stopPrank();

        bytes memory payload = abi.encode(user, tokenId, unlockAmount);

        vm.prank(address(bscEndpoint));
        vm.expectRevert(abi.encodeWithSelector(
            PredictionMarketEscrow.InsufficientLockedBalance.selector,
            tokenId, uint256(lockAmount), unlockAmount
        ));
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: bridgeReceiverPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );
    }

    function testFuzz_unlock_worksWhenPaused(
        uint256 tokenId,
        uint128 amount
    ) public {
        vm.assume(amount > 0);

        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        predictionMarketToken.mint(user, tokenId, amount);

        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(tokenId, amount, makeAddr("poly"), _option);
        vm.stopPrank();

        vm.prank(owner);
        escrow.pause();

        bytes memory payload = abi.encode(user, tokenId, uint256(amount));
        vm.prank(address(bscEndpoint));
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: bridgeReceiverPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );

        assertEq(predictionMarketToken.balanceOf(user, tokenId), amount);
        assertEq(escrow.totalLocked(tokenId), 0);
    }

    function testFuzz_lock_messagePayload(
        uint256 tokenId,
        uint128 amount,
        address polygonRecipient
    ) public {
        vm.assume(polygonRecipient != address(0));
        vm.assume(amount > 0);

        address user = makeAddr("user");
        vm.deal(user, 10 ether);
        predictionMarketToken.mint(user, tokenId, amount);

        vm.startPrank(user);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(tokenId, amount, polygonRecipient, _option);
        vm.stopPrank();

        MockEndpointV2.StoredMessage memory msg_ = bscEndpoint.lastMessage();
        (address decodedRecipient, uint256 decodedTokenId, uint256 decodedAmount) =
            abi.decode(msg_.message, (address, uint256, uint256));

        assertEq(decodedRecipient, polygonRecipient);
        assertEq(decodedTokenId, tokenId);
        assertEq(decodedAmount, amount);
    }

    function testFuzz_setDstGasLimit(uint128 gasLimit) public {
        vm.prank(owner);
        escrow.setDstGasLimit(gasLimit);
        assertEq(escrow.dstGasLimit(), gasLimit);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Integration Fuzz Tests — full round-trip with cross-chain message delivery
// ══════════════════════════════════════════════════════════════════════════════

contract BridgeIntegrationFuzzTest is Test {
    uint32 constant BSC_EID = 30102;
    uint32 constant POLYGON_EID = 30109;

    MockEndpointV2 public bscEndpoint;
    MockEndpointV2 public polyEndpoint;
    PredictionMarketEscrow public escrow;
    BridgeReceiver public receiver;
    WrappedPredictionToken public wrappedToken;
    MockERC1155 public predictionMarketToken;

    address public deployer = makeAddr("deployer");

    bytes public _option = abi.encodePacked(
        uint16(0x0003), uint8(0x01), uint16(0x0011), uint8(0x01), uint128(400_000)
    );

    function setUp() public {
        bscEndpoint = new MockEndpointV2(BSC_EID);
        polyEndpoint = new MockEndpointV2(POLYGON_EID);
        predictionMarketToken = new MockERC1155();

        vm.startPrank(deployer);
        escrow = new PredictionMarketEscrow(address(bscEndpoint), deployer, address(predictionMarketToken), POLYGON_EID);
        wrappedToken = new WrappedPredictionToken(deployer, address(predictionMarketToken));
        receiver = new BridgeReceiver(address(polyEndpoint), deployer, address(wrappedToken), BSC_EID);

        wrappedToken.setBridge(address(receiver));
        escrow.setPeer(POLYGON_EID, bytes32(uint256(uint160(address(receiver)))));
        receiver.setPeer(BSC_EID, bytes32(uint256(uint160(address(escrow)))));
        escrow.setDstGasLimit(400_000);
        receiver.setDstGasLimit(400_000);
        escrow.unpause();
        receiver.unpause();
        vm.stopPrank();
    }

    function testFuzz_fullRoundTrip(uint256 tokenId, uint128 amount) public {
        vm.assume(amount > 0);

        address bscUser = makeAddr("bscUser");
        address polyUser = makeAddr("polyUser");
        vm.deal(bscUser, 10 ether);
        vm.deal(polyUser, 10 ether);

        predictionMarketToken.mint(bscUser, tokenId, amount);

        // Lock on BSC
        vm.startPrank(bscUser);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(tokenId, amount, polyUser, _option);
        vm.stopPrank();

        assertEq(escrow.totalLocked(tokenId), amount);
        assertEq(predictionMarketToken.balanceOf(address(escrow), tokenId), amount);

        // Deliver to Polygon
        bscEndpoint.deliverMessage(0, polyEndpoint);

        assertEq(wrappedToken.balanceOf(polyUser, tokenId), amount);
        assertEq(receiver.totalBridged(tokenId), amount);
        assertEq(wrappedToken.totalSupply(tokenId), amount);

        // Bridge back
        vm.prank(polyUser);
        receiver.bridgeBack{value: 0.01 ether}(tokenId, amount, bscUser, _option);

        assertEq(wrappedToken.balanceOf(polyUser, tokenId), 0);
        assertEq(receiver.totalBridged(tokenId), 0);

        // Deliver unlock to BSC
        polyEndpoint.deliverMessage(0, bscEndpoint);

        assertEq(predictionMarketToken.balanceOf(bscUser, tokenId), amount);
        assertEq(predictionMarketToken.balanceOf(address(escrow), tokenId), 0);
        assertEq(escrow.totalLocked(tokenId), 0);
    }

    function testFuzz_partialRoundTrip(
        uint256 tokenId,
        uint128 lockAmount,
        uint128 bridgeBackAmount
    ) public {
        vm.assume(lockAmount > 0);
        vm.assume(bridgeBackAmount > 0 && bridgeBackAmount <= lockAmount);

        address bscUser = makeAddr("bscUser");
        address polyUser = makeAddr("polyUser");
        vm.deal(bscUser, 10 ether);
        vm.deal(polyUser, 10 ether);

        predictionMarketToken.mint(bscUser, tokenId, lockAmount);

        vm.startPrank(bscUser);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(tokenId, lockAmount, polyUser, _option);
        vm.stopPrank();

        bscEndpoint.deliverMessage(0, polyEndpoint);

        vm.prank(polyUser);
        receiver.bridgeBack{value: 0.01 ether}(tokenId, bridgeBackAmount, bscUser, _option);

        polyEndpoint.deliverMessage(0, bscEndpoint);

        uint256 remaining = uint256(lockAmount) - uint256(bridgeBackAmount);

        // Invariant: totalBridged == wrappedToken.totalSupply
        assertEq(receiver.totalBridged(tokenId), wrappedToken.totalSupply(tokenId));
        // Invariant: escrow balance == totalLocked
        assertEq(predictionMarketToken.balanceOf(address(escrow), tokenId), escrow.totalLocked(tokenId));
        // Remaining state checks
        assertEq(escrow.totalLocked(tokenId), remaining);
        assertEq(wrappedToken.balanceOf(polyUser, tokenId), remaining);
        assertEq(predictionMarketToken.balanceOf(bscUser, tokenId), bridgeBackAmount);
    }

    function testFuzz_multipleTokenTypes_invariants(
        uint128 amount1,
        uint128 amount2
    ) public {
        vm.assume(amount1 > 0 && amount2 > 0);

        uint256 tokenId1 = 1;
        uint256 tokenId2 = 2;
        address bscUser = makeAddr("bscUser");
        address polyUser = makeAddr("polyUser");
        vm.deal(bscUser, 10 ether);
        vm.deal(polyUser, 10 ether);

        predictionMarketToken.mint(bscUser, tokenId1, amount1);
        predictionMarketToken.mint(bscUser, tokenId2, amount2);

        vm.startPrank(bscUser);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(tokenId1, amount1, polyUser, _option);
        escrow.lock{value: 0.01 ether}(tokenId2, amount2, polyUser, _option);
        vm.stopPrank();

        bscEndpoint.deliverMessage(0, polyEndpoint);
        bscEndpoint.deliverMessage(1, polyEndpoint);

        // Invariants hold per token ID
        assertEq(receiver.totalBridged(tokenId1), wrappedToken.totalSupply(tokenId1));
        assertEq(receiver.totalBridged(tokenId2), wrappedToken.totalSupply(tokenId2));
        assertEq(predictionMarketToken.balanceOf(address(escrow), tokenId1), escrow.totalLocked(tokenId1));
        assertEq(predictionMarketToken.balanceOf(address(escrow), tokenId2), escrow.totalLocked(tokenId2));

        // Token IDs are independent
        assertEq(escrow.totalLocked(tokenId1), amount1);
        assertEq(escrow.totalLocked(tokenId2), amount2);
    }

    function testFuzz_multipleUsers_invariants(
        uint128 aliceAmount,
        uint128 bobAmount
    ) public {
        vm.assume(aliceAmount > 0 && bobAmount > 0);

        uint256 tokenId = 1;
        address aliceBsc = makeAddr("aliceBsc");
        address alicePoly = makeAddr("alicePoly");
        address bobBsc = makeAddr("bobBsc");
        address bobPoly = makeAddr("bobPoly");
        vm.deal(aliceBsc, 10 ether);
        vm.deal(bobBsc, 10 ether);

        predictionMarketToken.mint(aliceBsc, tokenId, aliceAmount);
        predictionMarketToken.mint(bobBsc, tokenId, bobAmount);

        vm.startPrank(aliceBsc);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(tokenId, aliceAmount, alicePoly, _option);
        vm.stopPrank();

        vm.startPrank(bobBsc);
        predictionMarketToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(tokenId, bobAmount, bobPoly, _option);
        vm.stopPrank();

        bscEndpoint.deliverMessage(0, polyEndpoint);
        bscEndpoint.deliverMessage(1, polyEndpoint);

        uint256 totalAmount = uint256(aliceAmount) + uint256(bobAmount);

        // Global invariants
        assertEq(escrow.totalLocked(tokenId), totalAmount);
        assertEq(receiver.totalBridged(tokenId), totalAmount);
        assertEq(wrappedToken.totalSupply(tokenId), totalAmount);
        assertEq(receiver.totalBridged(tokenId), wrappedToken.totalSupply(tokenId));

        // Per-user balances
        assertEq(wrappedToken.balanceOf(alicePoly, tokenId), aliceAmount);
        assertEq(wrappedToken.balanceOf(bobPoly, tokenId), bobAmount);
    }
}
