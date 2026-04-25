// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/// @title MockERC1155
/// @notice Simple ERC-1155 token for testing. Simulates prediction market token contract on BSC.
///         Anyone can mint (no access control) — only for testing.
contract MockERC1155 is ERC1155 {
    constructor() ERC1155("") {}

    function mint(address _to, uint256 _tokenId, uint256 _amount) external {
        _mint(_to, _tokenId, _amount, "");
    }

    function mintBatch(address _to, uint256[] calldata _tokenIds, uint256[] calldata _amounts) external {
        _mintBatch(_to, _tokenIds, _amounts, "");
    }
}
