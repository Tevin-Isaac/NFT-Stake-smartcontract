
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
 

 import "@openzeppelin/contracts/access/Ownable.sol";
 import "@openzeppelin/contracts/utils/Address.sol";
 import "@openzeppelin/contracts/utils/math/SafeMath.sol";
 import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
 import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
 import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
 import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
 import '@openzeppelin/contracts/utils/math/Math.sol';
 import "@openzeppelin/contracts/security/Pausable.sol";
 import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract NftStaking is Ownable, IERC721Receiver, ReentrancyGuard, Pausable {
    using Address for address;
    using SafeMath for uint;
    using EnumerableSet for EnumerableSet.UintSet; 
    
    //addresses 
    address nullAddress = 0x0000000000000000000000000000000000000000;
    address public stakingDestinationAddress;
    address public erc20Address;

    //uint256's 
    uint256 public expiration; 
    //rate governs how often you receive your token
    uint256 public rate; 

    // unstaking possible after LOCKUP_TIME
    uint public LOCKUP_TIME = 1 minutes;

    // Contracts are not allowed to deposit, claim or withdraw
    modifier noContractsAllowed() {
        require(!(address(msg.sender).isContract()) && tx.origin == msg.sender, "No Contracts Allowed!");
        _;
    }

    event RateChanged(uint256 newRate);
    event ExpirationChanged(uint256 newExpiration);
    event LockTimeChanged(uint newLockTime);
  
    // mappings 
    mapping(address => EnumerableSet.UintSet) private _deposits;
    mapping(address => mapping(uint256 => uint256)) public _depositBlocks;
    mapping (address => uint) public stakingTime;

    constructor(
      address _stakingDestinationAddress,
      uint256 _rate,
      uint256 _expiration,
      address _erc20Address
    ) {
        stakingDestinationAddress = _stakingDestinationAddress;
        rate = _rate;
        expiration = block.number + _expiration;
        erc20Address = _erc20Address;
        _pause();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

/* STAKING MECHANICS */

    // Set a multiplier for how many tokens to earn each time a block passes.
    function setRate(uint256 _rate) public onlyOwner() {
      rate = _rate;
      emit RateChanged(rate);
    }

    // Set this to a block to disable the ability to continue accruing tokens past that block number.
    function setExpiration(uint256 _expiration) public onlyOwner() {
      expiration = block.number + _expiration;
      emit ExpirationChanged(expiration);
    }

    //Set Lock Time
    function setLockTime(uint _lockTime) public onlyOwner() {
      LOCKUP_TIME = _lockTime;
      emit LockTimeChanged(LOCKUP_TIME);
    }

    //check deposit amount. 
    function depositsOf(address account)
      external 
      view 
      returns (uint256[] memory)
    {
      EnumerableSet.UintSet storage depositSet = _deposits[account];
      uint256[] memory tokenIds = new uint256[] (depositSet.length());

      for (uint256 i; i < depositSet.length(); i++) {
        tokenIds[i] = depositSet.at(i);
      }

      return tokenIds;
    }

    function calculateRewards(address account, uint256[] memory tokenIds) 
      public 
      view 
      returns (uint256[] memory rewards) 
    {
      rewards = new uint256[](tokenIds.length);

      for (uint256 i; i < tokenIds.length; i++) {
        uint256 tokenId = tokenIds[i];

        rewards[i] = 
          rate * 
          (_deposits[account].contains(tokenId) ? 1 : 0) * 
          (Math.min(block.number, expiration) - 
            _depositBlocks[account][tokenId]);
      }

      return rewards;
    }

    //reward amount by address/tokenIds[]
    function calculateReward(address account, uint256 tokenId) 
      public 
      view 
      returns (uint256) 
    {
      // require(Math.min(block.number, expiration) > _depositBlocks[account][tokenId], "Invalid blocks");
      return rate * 
          (_deposits[account].contains(tokenId) ? 1 : 0) * 
          (Math.min(block.number, expiration) - 
            _depositBlocks[account][tokenId]);
    }

    //Update Account and Auto-claim 
    function updateAccount(uint256[] calldata tokenIds) private {
      uint256 reward; 
      uint256 blockCur = Math.min(block.number, expiration);

      for (uint256 i; i < tokenIds.length; i++) {
        reward += calculateReward(msg.sender, tokenIds[i]);
        _depositBlocks[msg.sender][tokenIds[i]] = blockCur;
      }

      if (reward > 0) {
        require(IERC20(erc20Address).transfer(msg.sender, reward), "Could not transfer Reward Token!");
      }
    }

    //Reward claim function
    function claimRewards(uint256[] calldata tokenIds) external whenNotPaused noContractsAllowed nonReentrant(){
      updateAccount(tokenIds);
    }

    //deposit function. 
    function deposit(uint256[] calldata tokenIds) external whenNotPaused noContractsAllowed nonReentrant() {
        require(msg.sender != stakingDestinationAddress, "Invalid address");
        require(block.number < expiration, "Staking has finished, no more deposits!");
        updateAccount(tokenIds);

        for (uint256 i; i < tokenIds.length; i++) {
            IERC721(stakingDestinationAddress).safeTransferFrom(
                msg.sender,
                address(this),
                tokenIds[i],
                ""
            );

            _deposits[msg.sender].add(tokenIds[i]);
        }
        stakingTime[msg.sender] = block.timestamp;
    }

    //withdrawal function.
    function withdraw(uint256[] calldata tokenIds) external whenNotPaused noContractsAllowed nonReentrant() {

    	require(block.timestamp.sub(stakingTime[msg.sender]) > LOCKUP_TIME, "You recently staked, please wait before withdrawing.");

        updateAccount(tokenIds);

        for (uint256 i; i < tokenIds.length; i++) {
            require(
                _deposits[msg.sender].contains(tokenIds[i]),
                "Staking: token not deposited"
            );

            _deposits[msg.sender].remove(tokenIds[i]);

            IERC721(stakingDestinationAddress).safeTransferFrom(
                address(this),
                msg.sender,
                tokenIds[i],
                ""
            );
        }
    }

    //withdraw without caring about Rewards
    function emergencyWithdraw(uint256[] calldata tokenIds) external noContractsAllowed nonReentrant() {
        require(block.timestamp.sub(stakingTime[msg.sender]) > LOCKUP_TIME, "You recently staked, please wait before withdrawing.");
        
        for (uint256 i; i < tokenIds.length; i++) {
            require(
                _deposits[msg.sender].contains(tokenIds[i]),
                "Staking: token not deposited"
            );

            _deposits[msg.sender].remove(tokenIds[i]);

            IERC721(stakingDestinationAddress).safeTransferFrom(
                address(this),
                msg.sender,
                tokenIds[i],
                ""
            );
        }
    }

    //withdrawal function.
    function withdrawTokens() external onlyOwner {
        uint256 tokenSupply = IERC20(erc20Address).balanceOf(address(this));
        require(IERC20(erc20Address).transfer(msg.sender, tokenSupply), "Could not transfer Reward Token!");
    }

    // Prevent sending ERC721 tokens directly to this contract
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}