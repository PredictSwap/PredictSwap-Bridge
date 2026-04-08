// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3, EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title OpinionEscrow
/// @notice Deployed on BSC. Locks Opinion ERC-1155 shares in escrow and sends a LayerZero
///         message to BridgeReceiver on Polygon, which mints WrappedOpinionToken.
///         Receives unlock messages from Polygon to release shares back to users.
/// @dev Handles a single Opinion ERC-1155 contract (set as immutable).
///      If Opinion deploys a new contract, deploy a new OpinionEscrow.
///
/// ─── Deployment checklist ────────────────────────────────────────────────────
///
///   1. Deploy OpinionEscrow (contract starts paused)
///   2. setPeer(polygonEid, bytes32(uint256(uint160(bridgeReceiverAddress))))
///   3. setDstGasLimit(400_000)  — enforces minimum gas for _lzReceive on Polygon
///   4. unpause()
///
/// ─── Message flow ────────────────────────────────────────────────────────────
///
///   Lock   (BSC → Polygon): user calls lock() → LZ message → BridgeReceiver mints wrapped tokens
///   Unlock (Polygon → BSC): BridgeReceiver sends LZ message → _lzReceive() releases locked tokens
///
contract OpinionEscrow is OApp, OAppOptionsType3, IERC1155Receiver, ReentrancyGuard, Pausable {

    using SafeERC20 for IERC20;
    using OptionsBuilder for bytes;

    // ─── Immutable config ─────────────────────────────────────────────────────

    /// @notice The Opinion ERC-1155 contract this escrow handles.
    /// @dev Immutable — if Opinion deploys a new contract, deploy a new OpinionEscrow.
    address public immutable opinionContract;

    /// @notice LayerZero endpoint ID for the Polygon chain (where BridgeReceiver lives).
    /// @dev Mainnet: 30109. Used as destination EID for all outbound LZ messages.
    uint32 public immutable polygonEid;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Total locked per tokenId across all users.
    /// @dev Used to enforce the invariant: totalLocked[id] >= amount in any unlock message.
    ///      Prevents unlock messages from releasing more than was ever locked.
    mapping(uint256 tokenId => uint256 amount) public totalLocked;

    /// @notice Current enforced gas limit for _lzReceive execution on Polygon.
    /// @dev Stored for visibility only — the actual enforcement is via OAppOptionsType3
    ///      enforced options set in setDstGasLimit(). Must be set via setDstGasLimit()
    ///      before unpausing, otherwise callers with empty _options have no gas floor.
    uint128 public dstGasLimit;

    /// @notice LZ message type for lock/unlock messages. Used in enforced options.
    uint16 public constant SEND = 1;

    // ─── Errors ───────────────────────────────────────────────────────────────

    error ZeroAmount();
    error ZeroAddress();
    /// @param tokenId  The token ID for which unlock was attempted.
    /// @param locked   Current totalLocked balance for this tokenId.
    /// @param requested Amount requested to unlock.
    error InsufficientLockedBalance(uint256 tokenId, uint256 locked, uint256 requested);
    /// @param tokenId Token ID that still has locked balance.
    error CannotRescueLockedTokens(uint256 tokenId);

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted when a user locks tokens and sends a bridge message to Polygon.
    /// @param user             BSC address that called lock().
    /// @param tokenId          Opinion ERC-1155 token ID locked.
    /// @param amount           Number of tokens locked.
    /// @param polygonRecipient Polygon address that will receive wrapped tokens.
    event Locked(
        address indexed user,
        uint256 indexed tokenId,
        uint256 amount,
        address polygonRecipient
    );

    /// @notice Emitted when tokens are released back to a BSC recipient via LZ message.
    /// @param user    BSC address receiving the unlocked tokens.
    /// @param tokenId Opinion ERC-1155 token ID unlocked.
    /// @param amount  Number of tokens released.
    event Unlocked(address indexed user, uint256 indexed tokenId, uint256 amount);

    /// @notice Emitted when the enforced destination gas limit is updated.
    /// @param gasLimit New gas limit applied to LZ executor options on Polygon.
    event DstGasLimitSet(uint128 gasLimit);

    /// @notice Emitted when tokens are rescued by the owner.
    /// @param token   Token contract address (address(0) for ETH).
    /// @param tokenId ERC-1155 token ID (0 for ERC-20 and ETH).
    /// @param amount  Amount rescued.
    /// @param to      Recipient address.
    event TokensRescued(address indexed token, uint256 indexed tokenId, uint256 amount, address indexed to);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param _endpoint       LayerZero endpoint address on BSC.
    /// @param _owner          Contract owner — should be team multisig.
    /// @param _opinionContract Opinion ERC-1155 contract address on BSC.
    /// @param _polygonEid     LayerZero endpoint ID for Polygon (mainnet: 30109).
    constructor(
        address _endpoint,
        address _owner,
        address _opinionContract,
        uint32 _polygonEid
    ) OApp(_endpoint, _owner) Ownable(_owner) {
        if (_opinionContract == address(0)) revert ZeroAddress();
        opinionContract = _opinionContract;
        polygonEid = _polygonEid;
        _pause(); // Paused until setPeer + setDstGasLimit are called
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Pause lock(). Incoming unlock messages (_lzReceive) are unaffected
    ///         and will continue to process.
    function pause() external onlyOwner { _pause(); }

    /// @notice Unpause lock(). Should only be called after setPeer and setDstGasLimit.
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Set the minimum gas limit enforced for _lzReceive execution on Polygon.
    /// @dev    Updates both the dstGasLimit storage variable (for visibility) and the
    ///         OAppOptionsType3 enforced options (for actual enforcement). The enforced
    ///         option is merged with any caller-supplied options via combineOptions(),
    ///         so callers cannot send messages with less than this gas limit.
    ///         Must be called before unpausing. Recommended value: 200_000+.
    /// @param _gasLimit Minimum gas units for executor on Polygon. Must cover
    ///                  BridgeReceiver._lzReceive: totalBridged update + mint() + ERC-1155 transfer.
    function setDstGasLimit(uint128 _gasLimit) external onlyOwner {
        dstGasLimit = _gasLimit;
        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        bytes memory dstGasOption = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gasLimit, 0);
        opts[0] = EnforcedOptionParam({
            eid: polygonEid,
            msgType: SEND,
            options: dstGasOption
        });
        _setEnforcedOptions(opts);
        emit DstGasLimitSet(_gasLimit);
    }

    // ─── Lock (BSC → Polygon) ─────────────────────────────────────────────────

    /// @notice Lock Opinion ERC-1155 shares in escrow and bridge them to Polygon.
    /// @dev    Caller must approve this contract on the Opinion ERC-1155 contract first.
    ///         The LZ messaging fee must be passed as msg.value. Use quoteLockFee() to
    ///         estimate the required fee before calling. Any excess msg.value is refunded
    ///         to msg.sender by the LZ endpoint.
    /// @param _tokenId          Opinion ERC-1155 token ID to lock.
    /// @param _amount           Number of tokens to lock. Must be > 0.
    /// @param _polygonRecipient Address on Polygon to receive wrapped tokens. Must be non-zero.
    /// @param _options          Additional LZ executor options (e.g. extra gas). Pass empty
    ///                          bytes if none — enforced options provide the gas floor.
    /// @return receipt          LZ messaging receipt containing nonce and fee details.
    function lock(
        uint256 _tokenId,
        uint256 _amount,
        address _polygonRecipient,
        bytes calldata _options
    ) external payable whenNotPaused nonReentrant returns (MessagingReceipt memory receipt) {
        if (_amount == 0) revert ZeroAmount();
        if (_polygonRecipient == address(0)) revert ZeroAddress();

        totalLocked[_tokenId] += _amount;
        IERC1155(opinionContract).safeTransferFrom(msg.sender, address(this), _tokenId, _amount, "");

        bytes memory payload = abi.encode(_polygonRecipient, _tokenId, _amount);
        receipt = _lzSend(polygonEid, payload, combineOptions(polygonEid, SEND, _options), MessagingFee(msg.value, 0), payable(msg.sender));

        emit Locked(msg.sender, _tokenId, _amount, _polygonRecipient);
    }

    /// @notice Estimate the LZ messaging fee for a lock() call.
    /// @dev    Pass the same _options you intend to use in lock(). Fee is in native token (BNB).
    /// @param _tokenId          Opinion ERC-1155 token ID.
    /// @param _amount           Number of tokens (used for payload encoding only, not fee calculation).
    /// @param _polygonRecipient Polygon recipient address.
    /// @param _options          Additional LZ executor options. Pass empty bytes if none.
    /// @return fee              Estimated MessagingFee with nativeFee (BNB) and lzTokenFee.
    function quoteLockFee(
        uint256 _tokenId,
        uint256 _amount,
        address _polygonRecipient,
        bytes calldata _options
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(_polygonRecipient, _tokenId, _amount);
        fee = _quote(polygonEid, payload, combineOptions(polygonEid, SEND, _options), false);
    }

    // ─── Unlock (Polygon → BSC) ───────────────────────────────────────────────

    /// @notice Receives unlock messages from BridgeReceiver on Polygon and releases
    ///         locked Opinion tokens to the specified BSC recipient.
    /// @dev    Only callable by the LZ endpoint. Peer verification is enforced by OApp base.
    ///         Intentionally NOT gated by pause — users must always be able to retrieve
    ///         their tokens regardless of contract pause state.
    ///         Reverts if the requested amount exceeds totalLocked for this tokenId,
    ///         which should never happen under normal operation.
    function _lzReceive(
        Origin calldata, /* _origin */
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal override nonReentrant {
        (address bscRecipient, uint256 tokenId, uint256 amount) =
            abi.decode(_message, (address, uint256, uint256));

        if (totalLocked[tokenId] < amount) revert InsufficientLockedBalance(tokenId, totalLocked[tokenId], amount);

        totalLocked[tokenId] -= amount;
        IERC1155(opinionContract).safeTransferFrom(address(this), bscRecipient, tokenId, amount, "");

        emit Unlocked(bscRecipient, tokenId, amount);
    }

    // ─── Rescue ───────────────────────────────────────────────────────────────

    /// @notice Recover ERC-1155 tokens accidentally sent to this contract.
    /// @dev    Cannot rescue Opinion tokens for a tokenId that still has locked balance —
    ///         those belong to users awaiting unlock. Other ERC-1155 tokens (e.g. wrong
    ///         token sent by mistake) can always be rescued.
    /// @param _token   ERC-1155 token contract address.
    /// @param _tokenId Token ID to rescue.
    /// @param _amount  Amount to rescue.
    /// @param _to      Recipient address. Must be non-zero.
    function rescueTokens(
        address _token,
        uint256 _tokenId,
        uint256 _amount,
        address _to
    ) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        if (_token == opinionContract && totalLocked[_tokenId] > 0)
            revert CannotRescueLockedTokens(_tokenId);
        IERC1155(_token).safeTransferFrom(address(this), _to, _tokenId, _amount, "");
        emit TokensRescued(_token, _tokenId, _amount, _to);
    }

    /// @notice Recover ERC-20 tokens accidentally sent to this contract.
    /// @param _token  ERC-20 token contract address.
    /// @param _amount Amount to rescue.
    /// @param _to     Recipient address. Must be non-zero.
    function rescueERC20(address _token, uint256 _amount, address _to) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        IERC20(_token).safeTransfer(_to, _amount);
        emit TokensRescued(_token, 0, _amount, _to);
    }

    /// @notice Recover ETH accidentally sent to this contract.
    /// @param _to Recipient address. Must be non-zero.
    function rescueETH(address payable _to) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        uint256 balance = address(this).balance;
        (bool ok,) = _to.call{value: balance}("");
        require(ok, "ETH transfer failed");
        emit TokensRescued(address(0), 0, balance, _to);
    }

    receive() external payable {}

    // ─── ERC1155 Receiver ─────────────────────────────────────────────────────

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external pure returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}