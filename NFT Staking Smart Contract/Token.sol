// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC721 {
    function safeTransferFrom(
        address from,
        address to,
        uint tokenId
    ) external;

    function transferFrom(
        address,
        address,
        uint
    ) external;
}

contract MyToken is ERC20, Ownable, ReentrancyGuard{
     IERC721 public nft;
     mapping(uint256 => address) public tokenOwnerOf;
     mapping(uint256 => uint256) public tokenStakedAt;
     uint256 public emission_rate = 50 * 10 ^ decimals() / 1 days;


    constructor(address _nft) ERC20("MyToken", "MTK") {
        nft =IERC721(_nft);
    }

    // function mint(address to, uint256 amount) public onlyOwner {
    //     _mint(to, amount);
    // }

    modifier isTokenValid(uint tokenId) {
        require(tokenId >= 0, "Id doesn't exist");
        _;
    }

    function stake(uint256 tokenId) external isTokenValid(tokenId){
        nft.safeTransferFrom(msg.sender,address(this),tokenId);
        tokenOwnerOf[tokenId] = msg.sender;
        tokenStakedAt[tokenId] = block.timestamp;
    }

    function calculateTokens(uint256 tokenId) public isTokenValid(tokenId) view returns(uint256){
        uint256 timeElapsed = block.timestamp - tokenStakedAt[tokenId];
        return timeElapsed * emission_rate;
    }

    function unstake (uint256 tokenId)external isTokenValid(tokenId){
        _mint(msg.sender, calculateTokens(tokenId)); //minting the tokens for staking
        nft.transferFrom(address(this),msg.sender,tokenId);
        delete tokenOwnerOf[tokenId];
        delete tokenStakedAt[tokenId];


    }
}
