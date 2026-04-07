// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title WrappedOpinionToken
/// @notice ERC-1155 wrapped representation of Opinion prediction market shares on Polygon.
///         1:1 backed by locked shares in OpinionEscrow on BSC — for every token minted
///         here, exactly one Opinion share is locked in escrow on BSC.
/// @dev Only the authorized bridge (BridgeReceiver) can mint and burn tokens.
///      Token IDs match the original Opinion ERC-1155 token IDs exactly —
///      no remapping is performed.
///
/// ─── Deployment checklist ────────────────────────────────────────────────────
///
///   1. Deploy WrappedOpinionToken
///   2. Deploy BridgeReceiver (passing this contract's address)
///   3. setBridge(bridgeReceiverAddress) — one-time, irreversible
///
/// ─── Invariant ───────────────────────────────────────────────────────────────
///
///   totalSupply[tokenId] == BridgeReceiver.totalBridged[tokenId] at all times.
///   Any deviation indicates a bug or a failed LZ message.
///
contract WrappedOpinionToken is ERC1155, Ownable {

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice The BridgeReceiver contract authorized to mint and burn tokens.
    /// @dev Set once via setBridge(). Cannot be changed after being set.
    ///      Zero address means bridge has not been initialized yet — mint/burn will revert.
    address public bridge;

    /// @notice The Opinion ERC-1155 contract address on BSC that this token wraps.
    /// @dev Informational — used to document which BSC contract backs these tokens.
    ///      If Opinion deploys a new contract, a new WrappedOpinionToken must be deployed.
    address public immutable opinionContract;

    /// @notice Total supply per tokenId.
    /// @dev Maintained manually rather than relying on ERC1155 balanceOf scans,
    ///      for efficient on-chain accounting by SwapPool and other integrators.
    ///      Incremented on mint, decremented on burn.
    mapping(uint256 tokenId => uint256 supply) public totalSupply;

    // ─── Errors ───────────────────────────────────────────────────────────────

    /// @dev Thrown when a non-bridge address calls mint() or burn().
    error OnlyBridge();
    error ZeroAddress();
    error ZeroAmount();
    /// @dev Thrown when setBridge() is called after bridge has already been set.
    ///      Bridge address is permanent once assigned.
    error BridgeAlreadySet();

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted once when the BridgeReceiver address is permanently set.
    /// @param bridge Address of the authorized BridgeReceiver contract.
    event BridgeSet(address indexed bridge);

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyBridge() {
        if (msg.sender != bridge) revert OnlyBridge();
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param _owner           Contract owner — should be team multisig.
    /// @param _opinionContract The Opinion ERC-1155 contract address on BSC being wrapped.
    constructor(address _owner, address _opinionContract) ERC1155("") Ownable(_owner) {
        if (_opinionContract == address(0)) revert ZeroAddress();
        opinionContract = _opinionContract;
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Permanently set the BridgeReceiver contract address.
    /// @dev    One-time call — reverts if bridge is already set. This closes the
    ///         uninitialized bridge window: until this is called, mint() and burn()
    ///         revert via onlyBridge, so no tokens can be minted or burned.
    ///         Must be called before BridgeReceiver is unpaused.
    /// @param _bridge Address of the deployed BridgeReceiver contract. Must be non-zero.
    function setBridge(address _bridge) external onlyOwner {
        if (_bridge == address(0)) revert ZeroAddress();
        if (bridge != address(0)) revert BridgeAlreadySet();
        bridge = _bridge;
        emit BridgeSet(_bridge);
    }

    // ─── Mint / Burn (Bridge Only) ────────────────────────────────────────────

    /// @notice Mint wrapped tokens to a Polygon recipient.
    /// @dev    Called by BridgeReceiver._lzReceive() when a lock confirmation
    ///         arrives from OpinionEscrow on BSC. Caller must be the authorized bridge.
    ///         totalSupply[_tokenId] is incremented to keep pool accounting in sync.
    /// @param _to      Recipient address on Polygon. Must be non-zero.
    /// @param _tokenId Opinion ERC-1155 token ID — used directly as the wrapped token ID.
    /// @param _amount  Number of tokens to mint. Must be > 0.
    function mint(
        address _to,
        uint256 _tokenId,
        uint256 _amount
    ) external onlyBridge {
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        totalSupply[_tokenId] += _amount;
        _mint(_to, _tokenId, _amount, "");
    }

    /// @notice Burn wrapped tokens from a Polygon address.
    /// @dev    Called by BridgeReceiver.bridgeBack() when a user initiates a bridge-back
    ///         to BSC. Caller must be the authorized bridge.
    ///         Note: _burn() in OZ ERC1155 does not check token allowance — it burns
    ///         directly from _from. Security relies entirely on onlyBridge; BridgeReceiver
    ///         always passes msg.sender as _from so only the token holder can trigger a burn.
    ///         totalSupply[_tokenId] is decremented to keep pool accounting in sync.
    /// @param _from    Address whose tokens are burned — must hold sufficient balance.
    /// @param _tokenId The token ID to burn.
    /// @param _amount  Number of tokens to burn. Must be > 0.
    function burn(address _from, uint256 _tokenId, uint256 _amount) external onlyBridge {
        if (_amount == 0) revert ZeroAmount();
        totalSupply[_tokenId] -= _amount;
        _burn(_from, _tokenId, _amount);
    }
}