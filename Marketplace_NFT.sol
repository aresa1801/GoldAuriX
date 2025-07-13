// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract PropertyMarketplace is Ownable2Step, ReentrancyGuard {
    using Address for address;

    // Interfaces
    IERC1155 public immutable propertyNFT;
    IERC20 public immutable idrtToken;

    // Listing structure
    struct PropertyListing {
        address seller;
        uint256 propertyId;
        uint256 pricePerSquare; // Price per m² in IDRT
        uint256 totalArea;      // Total area listed (m²)
        uint256 availableArea;  // Remaining area (m²)
        bool isActive;
    }

    // Fee & tax configuration (in basis points: 1% = 100)
    uint256 public listingFeePerSquare = 500 * 10**18; // 500 IDRT per m²
    uint256 public transactionFeeBPS = 200;            // 2% of transaction
    uint256 public constant BPHTB_RATE = 500;         // 5%
    uint256 public constant PPH_RATE = 250;           // 2.5%
    uint256 public constant PPN_RATE = 1100;          // 11%

    // State variables
    mapping(uint256 => PropertyListing) private _listings;
    uint256[] private _activeListingIds;
    mapping(address => bool) private _verifiedDevelopers;

    // Events
    event PropertyListed(
        uint256 indexed listingId,
        address indexed seller,
        uint256 propertyId,
        uint256 pricePerSquare,
        uint256 totalArea
    );
    event PropertySold(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 areaPurchased,
        uint256 totalPrice,
        uint256 fees,
        uint256 taxes,
        uint256 netToSeller
    );
    event FeesUpdated(uint256 newListingFee, uint256 newTransactionFee);
    event DeveloperStatusUpdated(address developer, bool isVerified);

    // Modifiers
    modifier onlyActiveListing(uint256 listingId) {
        require(_listings[listingId].isActive, "Listing inactive");
        _;
    }

    constructor(address _propertyNFT, address _idrtToken) Ownable(msg.sender) {
        require(_propertyNFT != address(0), "Invalid NFT address");
        require(_idrtToken != address(0), "Invalid token address");
        propertyNFT = IERC1155(_propertyNFT);
        idrtToken = IERC20(_idrtToken);
    }

    // ================== CORE FUNCTIONS ==================

    /**
     * @notice List a property for sale
     * @param _propertyId The NFT property ID
     * @param _pricePerSquare Price per square meter in IDRT
     * @param _totalArea Total area to list (in m²)
     */
    function listProperty(
        uint256 _propertyId,
        uint256 _pricePerSquare,
        uint256 _totalArea
    ) external nonReentrant {
        require(_pricePerSquare > 0, "Price must be positive");
        require(_totalArea > 0, "Area must be positive");
        require(
            propertyNFT.balanceOf(msg.sender, _propertyId) >= _totalArea,
            "Insufficient balance"
        );

        // Calculate and transfer listing fee
        uint256 totalListingFee = listingFeePerSquare * _totalArea;
        _safeTransferFrom(idrtToken, msg.sender, address(this), totalListingFee);

        // Transfer NFT to escrow
        propertyNFT.safeTransferFrom(
            msg.sender,
            address(this),
            _propertyId,
            _totalArea,
            ""
        );

        // Create listing
        uint256 listingId = uint256(
            keccak256(abi.encodePacked(_propertyId, msg.sender, block.timestamp, _totalArea))
        );
        _listings[listingId] = PropertyListing({
            seller: msg.sender,
            propertyId: _propertyId,
            pricePerSquare: _pricePerSquare,
            totalArea: _totalArea,
            availableArea: _totalArea,
            isActive: true
        });

        _activeListingIds.push(listingId);
        emit PropertyListed(listingId, msg.sender, _propertyId, _pricePerSquare, _totalArea);
    }

    /**
     * @notice Purchase a portion of a listed property
     * @param _listingId The ID of the listing
     * @param _areaToBuy Area to purchase (in m²)
     */
    function buyProperty(
        uint256 _listingId,
        uint256 _areaToBuy
    ) external nonReentrant onlyActiveListing(_listingId) {
        PropertyListing storage listing = _listings[_listingId];
        require(_areaToBuy <= listing.availableArea, "Area exceeds availability");

        // Calculate costs
        uint256 totalPrice = listing.pricePerSquare * _areaToBuy;
        (uint256 taxAmount, uint256 feeAmount, uint256 netToSeller) = 
            _calculateTransactionCosts(totalPrice, listing.seller);
        uint256 totalCost = totalPrice + feeAmount + taxAmount;

        // Transfer funds
        _safeTransferFrom(idrtToken, msg.sender, address(this), totalCost);

        // Update listing
        listing.availableArea -= _areaToBuy;
        if (listing.availableArea == 0) {
            listing.isActive = false;
            _removeListing(_listingId);
        }

        // Transfer NFT to buyer
        propertyNFT.safeTransferFrom(
            address(this),
            msg.sender,
            listing.propertyId,
            _areaToBuy,
            ""
        );

        // Distribute funds
        _safeTransfer(idrtToken, listing.seller, netToSeller);

        emit PropertySold(
            _listingId,
            msg.sender,
            _areaToBuy,
            totalPrice,
            feeAmount,
            taxAmount,
            netToSeller
        );
    }

    // ================== ADMIN FUNCTIONS ==================

    function updateFees(
        uint256 _newListingFee,
        uint256 _newTransactionFee
    ) external onlyOwner {
        require(_newTransactionFee <= 500, "Fee too high"); // Max 5%
        listingFeePerSquare = _newListingFee;
        transactionFeeBPS = _newTransactionFee;
        emit FeesUpdated(_newListingFee, _newTransactionFee);
    }

    function setDeveloperStatus(
        address _developer,
        bool _isVerified
    ) external onlyOwner {
        _verifiedDevelopers[_developer] = _isVerified;
        emit DeveloperStatusUpdated(_developer, _isVerified);
    }

    function withdrawFees(address _recipient) external onlyOwner {
        uint256 balance = idrtToken.balanceOf(address(this));
        _safeTransfer(idrtToken, _recipient, balance);
    }

    // ================== VIEW FUNCTIONS ==================

    function getActiveListings() external view returns (uint256[] memory) {
        return _activeListingIds;
    }

    function getListingDetails(uint256 _listingId) external view returns (
        address seller,
        uint256 propertyId,
        uint256 pricePerSquare,
        uint256 totalArea,
        uint256 availableArea,
        bool isActive
    ) {
        PropertyListing memory listing = _listings[_listingId];
        return (
            listing.seller,
            listing.propertyId,
            listing.pricePerSquare,
            listing.totalArea,
            listing.availableArea,
            listing.isActive
        );
    }

    function calculatePurchaseCost(
        uint256 _listingId,
        uint256 _areaToBuy
    ) external view returns (
        uint256 totalPrice,
        uint256 platformFee,
        uint256 taxes,
        uint256 netToSeller,
        uint256 totalCost
    ) {
        PropertyListing memory listing = _listings[_listingId];
        require(listing.isActive, "Listing inactive");
        
        totalPrice = listing.pricePerSquare * _areaToBuy;
        (taxes, platformFee, netToSeller) = _calculateTransactionCosts(totalPrice, listing.seller);
        totalCost = totalPrice + platformFee + taxes;
    }

    // ================== INTERNAL FUNCTIONS ==================

    function _calculateTransactionCosts(
        uint256 _totalPrice,
        address _seller
    ) internal view returns (
        uint256 taxAmount,
        uint256 feeAmount,
        uint256 netToSeller
    ) {
        // Platform fee
        feeAmount = (_totalPrice * transactionFeeBPS) / 10_000;
        
        // Taxes (BPHTB + PPH)
        taxAmount = (_totalPrice * (BPHTB_RATE + PPH_RATE)) / 10_000;
        
        // Add PPN if seller is a verified developer
        if (_verifiedDevelopers[_seller]) {
            taxAmount += (_totalPrice * PPN_RATE) / 10_000;
        }
        
        netToSeller = _totalPrice - feeAmount - taxAmount;
    }

    function _removeListing(uint256 _listingId) internal {
        for (uint256 i = 0; i < _activeListingIds.length; i++) {
            if (_activeListingIds[i] == _listingId) {
                _activeListingIds[i] = _activeListingIds[_activeListingIds.length - 1];
                _activeListingIds.pop();
                break;
            }
        }
    }

    function _safeTransfer(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        require(token.transfer(to, amount), "Transfer failed");
    }

    function _safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        require(token.transferFrom(from, to, amount), "Transfer failed");
    }
}