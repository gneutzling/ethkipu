// SPDX-License-Identifier: MIT

pragma solidity >=0.8.24 <0.9.0;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract CobaiaNFT is ERC721, Ownable {
    uint256 private _nextTokenId;
    string private _baseTokenURI;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_
    )
        ERC721(name_, symbol_)
        Ownable(msg.sender)
    {
        _baseTokenURI = baseURI_;
    }


    function safeMint(address to) external onlyOwner returns (uint256 tokenId) {
        tokenId = ++_nextTokenId;
        _safeMint(to, tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    function totalMinted() external view returns (uint256) {
        return _nextTokenId;
    }
}
