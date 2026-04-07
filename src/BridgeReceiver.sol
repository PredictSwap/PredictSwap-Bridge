// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3, EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {WrappedOpinionToken} from "./WrappedOpinionToken.sol";

/// @title BridgeReceiver
/// @notice Deployed on Polygon. Receives lock confirmations from OpinionEscrow on BSC
///         and mints WrappedOpinionToken. Handles bridge-back requests by burning wrapped
///         tokens and sending unlock messages to BSC.
/// @dev Paired 1:1 with a single OpinionEscrow on BSC. If OpinionEscrow is redeployed,
///      a new BridgeReceiver must also be deployed and wired via setPeer.
///
/// ─── Deployment checklist ────────────────────────────────────────────────────
///
///   1. Deploy WrappedOpinionToken
///   2. Deploy BridgeReceiver (contract starts paused)
///   3. WrappedOpinionToken.setBridge(bridgeReceiverAddress) — one-time, irreversible
///   4. setPeer(bscEid, bytes32(uint256(uint160(opinionEscrowAddress))))
///   5. setDstGasLimit(400_000)  — enforces minimum gas for _lzReceive on BSC
///   6. unpause()
///
/// ─── Message flow ────────────────────────────────────────────────────────────
///
///   Bridge in  (BSC → Polygon): OpinionEscrow sends LZ message → _lzReceive() mints wrapped tokens
///   Bridge back (Polygon → BSC): user calls bridgeBack() → burns wrapped tokens → LZ message → OpinionEscrow releases locked tokens
///
/// ─── Invariant ───────────────────────────────────────────────────────────────
///
///   totalBridged[tokenId] == WrappedOpinionToken.totalSupply(tokenId) at all times.
///   Any deviation indicates a bug or a failed LZ message.
///
contract BridgeReceiver is OApp, OAppOptionsType3, Pausable {

    using SafeERC20 for IERC20;
    using OptionsBuilder for bytes;

    // ─── Immutable config ─────────────────────────────────────────────────────

    /// @notice The WrappedOpinionToken contract this bridge mints and burns.
    /// @dev Set at construction and immutable. WrappedOpinionToken.setBridge() must
    ///      be called with this contract's address before any messages can be processed.
    WrappedOpinionToken public immutable wrappedToken;

    /// @notice LayerZero endpoint ID for BSC (where OpinionEscrow lives).
    /// @dev Mainnet: 30102. Used as destination EID for all outbound LZ messages.
    uint32 public immutable bscEid;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Current enforced gas limit for _lzReceive execution on BSC.
    /// @dev Stored for visibility only — actual enforcement is via OAppOptionsType3
    ///      enforced options set in setDstGasLimit(). Must be set via setDstGasLimit()
    ///      before unpausing, otherwise callers with empty _options have no gas floor.
    uint128 public dstGasLimit;

    /// @notice LZ message type for bridge messages. Used in enforced options.
    uint16 public constant SEND = 1;

    /// @notice Total wrapped tokens minted per tokenId.
    /// @dev Safety invariant: must equal WrappedOpinionToken.totalSupply(tokenId) at all times.
    ///      Incremented on _lzReceive (bridge in), decremented on bridgeBack (bridge back).
    ///      Guards against releasing more than was ever bridged in.
    mapping(uint256 tokenId => uint256 amount) public totalBridged;

    // ─── Errors ───────────────────────────────────────────────────────────────

    error ZeroAmount();
    error ZeroAddress();
    /// @param tokenId   The token ID for which bridge-back was attempted.
    /// @param locked    Current totalBridged balance for this tokenId.
    /// @param requested Amount requested to bridge back.
    error InsufficientBridgedBalance(uint256 tokenId, uint256 locked, uint256 requested);
    /// @param tokenId Token ID that still has bridged balance outstanding.
    error CannotRescueLockedTokens(uint256 tokenId);

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted when wrapped tokens are minted after a successful bridge-in from BSC.
    /// @param polygonRecipient Address on Polygon that received the minted wrapped tokens.
    /// @param tokenId          Opinion ERC-1155 token ID that was bridged.
    /// @param amount           Number of wrapped tokens minted.
    event BridgedIn(
        address indexed polygonRecipient,
        uint256 indexed tokenId,
        uint256 amount
    );

    /// @notice Emitted when wrapped tokens are burned and an unlock message is sent to BSC.
    /// @param polygonSender Address on Polygon that initiated the bridge-back.
    /// @param bscRecipient  Address on BSC that will receive the unlocked Opinion tokens.
    /// @param tokenId       Opinion ERC-1155 token ID being bridged back.
    /// @param amount        Number of wrapped tokens burned.
    event BridgedBack(
        address indexed polygonSender,
        address indexed bscRecipient,
        uint256 tokenId,
        uint256 amount
    );

    /// @notice Emitted when the enforced destination gas limit is updated.
    /// @param gasLimit New gas limit applied to LZ executor options on BSC.
    event DstGasLimitSet(uint128 gasLimit);

    /// @notice Emitted when tokens are rescued by the owner.
    /// @param token   Token contract address (address(0) for ETH).
    /// @param tokenId ERC-1155 token ID (0 for ERC-20 and ETH).
    /// @param amount  Amount rescued.
    /// @param to      Recipient address.
    event TokensRescued(address indexed token, uint256 indexed tokenId, uint256 amount, address indexed to);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param _endpoint     LayerZero endpoint address on Polygon.
    /// @param _owner        Contract owner — should be team multisig.
    /// @param _wrappedToken Address of the WrappedOpinionToken contract on Polygon.
    /// @param _bscEid       LayerZero endpoint ID for BSC (mainnet: 30102).
    constructor(
        address _endpoint,
        address _owner,
        address _wrappedToken,
        uint32 _bscEid
    ) OApp(_endpoint, _owner) Ownable(_owner) {
        if (_wrappedToken == address(0)) revert ZeroAddress();
        wrappedToken = WrappedOpinionToken(_wrappedToken);
        bscEid = _bscEid;
        _pause(); // Paused until setPeer + WrappedToken.setBridge + setDstGasLimit are called
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Pause bridgeBack(). Incoming bridge-in messages (_lzReceive) are unaffected
    ///         and will continue to mint — in-flight BSC→Polygon messages always land.
    function pause() external onlyOwner { _pause(); }

    /// @notice Unpause bridgeBack(). Should only be called after setPeer and setDstGasLimit.
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Set the minimum gas limit enforced for _lzReceive execution on BSC.
    /// @dev    Updates both the dstGasLimit storage variable (for visibility) and the
    ///         OAppOptionsType3 enforced options (for actual enforcement). The enforced
    ///         option is merged with any caller-supplied options via combineOptions(),
    ///         so callers cannot send messages with less than this gas limit.
    ///         Must be called before unpausing. Recommended value: 200_000+.
    /// @param _gasLimit Minimum gas units for executor on BSC. Must cover
    ///                  OpinionEscrow._lzReceive: totalLocked update + safeTransferFrom.
    function setDstGasLimit(uint128 _gasLimit) external onlyOwner {
        dstGasLimit = _gasLimit;
        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        bytes memory dstGasOption = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gasLimit, 0);
        opts[0] = EnforcedOptionParam({
            eid: bscEid,
            msgType: SEND,
            options: dstGasOption
        });
        _setEnforcedOptions(opts);
        emit DstGasLimitSet(_gasLimit);
    }

    // ─── Receive Lock Confirmation (BSC → Polygon) ────────────────────────────

    /// @notice Receives bridge-in messages from OpinionEscrow on BSC and mints
    ///         wrapped tokens to the specified Polygon recipient.
    /// @dev    Only callable by the LZ endpoint. Peer verification is enforced by OApp base.
    ///         Intentionally NOT gated by pause — in-flight BSC→Polygon messages must
    ///         always be able to land and mint, regardless of contract pause state.
    ///         totalBridged is incremented here and must stay in sync with
    ///         WrappedOpinionToken.totalSupply(tokenId).
    function _lzReceive(
        Origin calldata, /* _origin */
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal override {
        (address polygonRecipient, uint256 tokenId, uint256 amount) =
            abi.decode(_message, (address, uint256, uint256));

        totalBridged[tokenId] += amount;
        wrappedToken.mint(polygonRecipient, tokenId, amount);

        emit BridgedIn(polygonRecipient, tokenId, amount);
    }

    // ─── Bridge Back (Polygon → BSC) ──────────────────────────────────────────

    /// @notice Burn wrapped tokens on Polygon and bridge them back to BSC.
    /// @dev    Caller must hold sufficient WrappedOpinionToken balance for _tokenId.
    ///         The LZ messaging fee must be passed as msg.value. Use quoteBridgeBackFee()
    ///         to estimate the required fee before calling. Any excess msg.value is
    ///         refunded to msg.sender by the LZ endpoint.
    ///         Burns before sending the LZ message — if _lzSend reverts, the entire
    ///         transaction reverts atomically and no tokens are lost.
    /// @param _tokenId      WrappedOpinionToken token ID to burn and bridge back.
    /// @param _amount       Number of tokens to burn. Must be > 0.
    /// @param _bscRecipient Address on BSC to receive the unlocked Opinion tokens. Must be non-zero.
    /// @param _options      Additional LZ executor options (e.g. extra gas). Pass empty
    ///                      bytes if none — enforced options provide the gas floor.
    /// @return receipt      LZ messaging receipt containing nonce and fee details.
    function bridgeBack(
        uint256 _tokenId,
        uint256 _amount,
        address _bscRecipient,
        bytes calldata _options
    ) external payable whenNotPaused returns (MessagingReceipt memory receipt) {
        if (_amount == 0) revert ZeroAmount();
        if (_bscRecipient == address(0)) revert ZeroAddress();
        if (totalBridged[_tokenId] < _amount) revert InsufficientBridgedBalance(_tokenId, totalBridged[_tokenId], _amount);

        totalBridged[_tokenId] -= _amount;
        wrappedToken.burn(msg.sender, _tokenId, _amount);

        bytes memory payload = abi.encode(_bscRecipient, _tokenId, _amount);
        receipt = _lzSend(bscEid, payload, combineOptions(bscEid, SEND, _options), MessagingFee(msg.value, 0), payable(msg.sender));

        emit BridgedBack(msg.sender, _bscRecipient, _tokenId, _amount);
    }

    /// @notice Estimate the LZ messaging fee for a bridgeBack() call.
    /// @dev    Pass the same _options you intend to use in bridgeBack(). Fee is in native token (MATIC).
    /// @param _tokenId      WrappedOpinionToken token ID.
    /// @param _amount       Number of tokens (used for payload encoding only, not fee calculation).
    /// @param _bscRecipient BSC recipient address.
    /// @param _options      Additional LZ executor options. Pass empty bytes if none.
    /// @return fee          Estimated MessagingFee with nativeFee (MATIC) and lzTokenFee.
    function quoteBridgeBackFee(
        uint256 _tokenId,
        uint256 _amount,
        address _bscRecipient,
        bytes calldata _options
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(_bscRecipient, _tokenId, _amount);
        fee = _quote(bscEid, payload, combineOptions(bscEid, SEND, _options), false);
    }

    // ─── Rescue ───────────────────────────────────────────────────────────────

    /// @notice Recover ERC-1155 tokens accidentally sent to this contract.
    /// @dev    Cannot rescue WrappedOpinionToken for a tokenId that still has outstanding
    ///         bridged balance — those represent user funds awaiting bridge-back.
    ///         Other ERC-1155 tokens sent by mistake can always be rescued.
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
        if (_token == address(wrappedToken) && totalBridged[_tokenId] > 0)
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
}