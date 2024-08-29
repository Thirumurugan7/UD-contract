// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NumberSubscription is ERC721URIStorage, ReentrancyGuard {
    struct Subscription {
        uint256 endTime;
        uint256 pricePaid;
        uint256 subscriptionDuration;
    }

    mapping(uint256 => Subscription) public subscriptions;
    mapping(uint256 => uint256) public highestBid;
    mapping(uint256 => address) public highestBidder;
    mapping(uint256 => uint256) public numberToTokenId;
    uint256[] public biddingNumbers;

    uint256 public constant ONE_YEAR = 2 minutes;
    uint256 public renewalFeePercentage = 30;

    event SubscriptionRegistered(uint256 indexed tokenId, address subscriber, uint256 duration);
    event SubscriptionRenewed(uint256 indexed tokenId, address owner, uint256 newEndTime);
    event BidPlaced(uint256 indexed tokenId, address bidder, uint256 bid);
    event SubscriptionExpired(uint256 indexed tokenId, address newOwner);
    event SubscriptionTransferred(uint256 indexed tokenId, address from, address to);

    constructor() ERC721("NumberSubscription", "NUMSUB") {}

    function registerNumber(uint256 number, uint256 duration) external payable {
        require(duration == 1 || duration == 3 || duration == 5, "Invalid duration");
        uint256 tokenId = uint256(keccak256(abi.encodePacked(number)));

        uint256 price = calculatePrice(duration);
        require(msg.value == price, "Incorrect value sent");

        _mint(msg.sender, tokenId);
        subscriptions[tokenId] = Subscription(block.timestamp + (duration * ONE_YEAR), msg.value, duration);
        numberToTokenId[number] = tokenId;

        emit SubscriptionRegistered(tokenId, msg.sender, duration);
    }

    function calculatePrice(uint256 duration) public pure returns (uint256) {
        if (duration == 1) return 0.0000000001 ether; //30 
        if (duration == 3) return 0.00000001 ether;// 45
        if (duration == 5) return 0.00001 ether; //60
        return 0; 
    }

    function placeBid(uint256 number) external payable {
        uint256 tokenId = numberToTokenId[number];
        require(msg.value > highestBid[tokenId], "Higher bid required");

        if (highestBid[tokenId] == 0) {
            biddingNumbers.push(number); // Add to bidding list if it's the first bid
        }

        if (highestBid[tokenId] > 0) {
            payable(highestBidder[tokenId]).transfer(highestBid[tokenId]); // Refund previous highest bidder
        }

        highestBid[tokenId] = msg.value;
        highestBidder[tokenId] = msg.sender;

        emit BidPlaced(tokenId, msg.sender, msg.value);
    }

    function renewSubscription(uint256 number) external payable nonReentrant {
        uint256 tokenId = numberToTokenId[number];
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        require(block.timestamp >= subscriptions[tokenId].endTime, "Subscription not yet expired");

        uint256 renewalFee = subscriptions[tokenId].pricePaid * renewalFeePercentage / 100;
        require(msg.value >= (highestBid[tokenId] > 0 ? highestBid[tokenId] : renewalFee), "Incorrect fee");

        subscriptions[tokenId].endTime += subscriptions[tokenId].subscriptionDuration * ONE_YEAR;
        subscriptions[tokenId].pricePaid = msg.value;

        emit SubscriptionRenewed(tokenId, msg.sender, subscriptions[tokenId].endTime);
    }

    function getSubscriptionDetails(uint256 number) public view returns (uint256 endTime, uint256 renewalAmount, bool isCurrentlyBidded, address owner) {
        uint256 tokenId = numberToTokenId[number];

        endTime = subscriptions[tokenId].endTime;
        renewalAmount = highestBid[tokenId] > 0 ? highestBid[tokenId] : (subscriptions[tokenId].pricePaid * renewalFeePercentage / 100);
        isCurrentlyBidded = highestBid[tokenId] > 0;
        owner = ownerOf(tokenId);

        return (endTime, renewalAmount, isCurrentlyBidded, owner);
    }

    function getOwnerOfNumber(uint256 number) public view returns (address) {
        uint256 tokenId = numberToTokenId[number];
        return ownerOf(tokenId);
    }

      function resolveExpiration(uint256 number) public nonReentrant {
        uint256 tokenId = numberToTokenId[number];
        require(block.timestamp >= subscriptions[tokenId].endTime, "Subscription not yet expired");
        
        if (highestBid[tokenId] > 0 && highestBidder[tokenId] != address(0)) {
            // If there is a highest bidder, transfer the NFT to them
            _transfer(ownerOf(tokenId), highestBidder[tokenId], tokenId);
            emit SubscriptionTransferred(tokenId, ownerOf(tokenId), highestBidder[tokenId]);
        } else {
            // No action taken if no bids were placed
            emit SubscriptionExpired(tokenId, ownerOf(tokenId));
        }
    }

}
