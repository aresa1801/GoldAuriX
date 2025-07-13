// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract PropertyNFT is ERC1155, AccessControl {
    using Strings for uint256;

    // Role definitions
    bytes32 public constant BPN_ADMIN = keccak256("BPN_ADMIN");
    bytes32 public constant FEE_ADMIN = keccak256("FEE_ADMIN");
    bytes32 public constant TEST_ADMIN = keccak256("TEST_ADMIN");

    // Token payment configuration
    IERC20 public immutable idrtToken;
    uint256 public constant FEE_PER_METER = 1000 * 10**18; // 1000 IDRT (18 decimals) per m²

    // Property data structure
    struct PropertyInfo {
        string propertyName;
        uint256 totalLandArea;    // in square meters
        uint256 mintedLandArea;   // in square meters
        string certificateType;
        string certificateNumber;
        string certificatePhotoCID; // IPFS CID for document
        string district;          // Kabupaten/Kota
        bool verified;
        address projectOwner;
    }

    // Storage mappings
    mapping(uint256 => PropertyInfo) public properties;
    mapping(string => bool) public usedCertificateNumbers;
    mapping(string => address) public districtVerifiers;
    mapping(uint256 => mapping(address => uint256)) private _balances;

    // Testing features
    bool public autoVerificationEnabled = false;

    // Events
    event PropertyRegistered(
        uint256 indexed propertyId,
        address indexed owner,
        string certificateNumber,
        string district
    );
    event LandMinted(
        uint256 indexed propertyId,
        address indexed owner,
        uint256 landArea
    );
    event PropertyVerified(
        uint256 indexed propertyId,
        address indexed verifier
    );
    event DistrictVerifierAdded(
        string district,
        address verifier
    );
    event DistrictVerifierRemoved(
        string district
    );
    event AutoVerificationToggled(
        bool enabled
    );

    constructor(address _idrtToken) ERC1155("https://api.property-nft.com/metadata/{id}.json") {
        require(_idrtToken != address(0), "Invalid token address");
        idrtToken = IERC20(_idrtToken);
        
        // Setup initial roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BPN_ADMIN, msg.sender);
        _grantRole(FEE_ADMIN, msg.sender);
        _grantRole(TEST_ADMIN, msg.sender);
    }

    // ================== TESTING FEATURES ==================
    function toggleAutoVerification() external onlyRole(TEST_ADMIN) {
        autoVerificationEnabled = !autoVerificationEnabled;
        emit AutoVerificationToggled(autoVerificationEnabled);
    }

    // ================== PROPERTY REGISTRATION ==================
    function registerProperty(
        string memory _propertyName,
        uint256 _totalLandArea,
        string memory _certificateType,
        string memory _certificateNumber,
        string memory _certificatePhotoCID,
        string memory _district
    ) external returns (uint256) {
        require(_totalLandArea > 0, "Land area must be positive");
        require(!usedCertificateNumbers[_certificateNumber], "Certificate number already used");
        
        if (!autoVerificationEnabled) {
            require(districtVerifiers[_district] != address(0), "District verifier not set");
        }

        uint256 propertyId = uint256(keccak256(abi.encodePacked(_certificateNumber)));
        
        properties[propertyId] = PropertyInfo({
            propertyName: _propertyName,
            totalLandArea: _totalLandArea,
            mintedLandArea: 0,
            certificateType: _certificateType,
            certificateNumber: _certificateNumber,
            certificatePhotoCID: _certificatePhotoCID,
            district: _district,
            verified: autoVerificationEnabled,
            projectOwner: msg.sender
        });

        usedCertificateNumbers[_certificateNumber] = true;

        emit PropertyRegistered(propertyId, msg.sender, _certificateNumber, _district);
        
        if (autoVerificationEnabled) {
            emit PropertyVerified(propertyId, msg.sender);
        }
        
        return propertyId;
    }

    // ================== LAND MINTING ==================
    function mintLandArea(
        uint256 _propertyId,
        uint256 _landArea,
        address _recipient
    ) external {
        PropertyInfo storage property = properties[_propertyId];
        require(property.projectOwner != address(0), "Property not registered");
        require(!property.verified || autoVerificationEnabled, "Property already verified");
        require(
            property.mintedLandArea + _landArea <= property.totalLandArea,
            "Exceeds total land area"
        );

        uint256 totalFee = FEE_PER_METER * _landArea;
        require(
            idrtToken.transferFrom(msg.sender, address(this), totalFee),
            "Payment failed"
        );

        _mint(_recipient, _propertyId, _landArea, "");
        property.mintedLandArea += _landArea;

        if (autoVerificationEnabled && property.mintedLandArea == property.totalLandArea) {
            property.verified = true;
            emit PropertyVerified(_propertyId, msg.sender);
        }

        emit LandMinted(_propertyId, _recipient, _landArea);
    }

    // ================== BPN VERIFICATION ==================
    function verifyProperty(uint256 _propertyId) external {
        require(!autoVerificationEnabled, "Auto verification enabled");
        
        PropertyInfo storage property = properties[_propertyId];
        require(property.projectOwner != address(0), "Property not registered");
        require(!property.verified, "Already verified");
        require(
            property.mintedLandArea == property.totalLandArea,
            "Not all land area minted"
        );
        require(
            msg.sender == districtVerifiers[property.district],
            "Only designated district verifier"
        );

        property.verified = true;
        emit PropertyVerified(_propertyId, msg.sender);
    }

    // ================== ADMIN FUNCTIONS ==================
    function addDistrictVerifier(
        string memory _district,
        address _verifier
    ) external onlyRole(BPN_ADMIN) {
        require(_verifier != address(0), "Invalid verifier address");
        require(districtVerifiers[_district] == address(0), "Verifier already exists");
        
        districtVerifiers[_district] = _verifier;
        emit DistrictVerifierAdded(_district, _verifier);
    }

    function removeDistrictVerifier(
        string memory _district
    ) external onlyRole(BPN_ADMIN) {
        require(districtVerifiers[_district] != address(0), "Verifier not found");
        
        districtVerifiers[_district] = address(0);
        emit DistrictVerifierRemoved(_district);
    }

    function withdrawFees(
        address _recipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = idrtToken.balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        idrtToken.transfer(_recipient, balance);
    }

    // ================== VIEW FUNCTIONS ==================
    function getPropertyInfo(
        uint256 _propertyId
    ) external view returns (PropertyInfo memory) {
        return properties[_propertyId];
    }

    function getDistrictVerifier(
        string memory _district
    ) external view returns (address) {
        return districtVerifiers[_district];
    }

    function uri(
        uint256 _propertyId
    ) public view override returns (string memory) {
        PropertyInfo memory property = properties[_propertyId];
        require(property.projectOwner != address(0), "Property not found");

        string memory verifiedStatus = property.verified ? "Verified" : "Pending Verification";
        string memory autoVerifStatus = autoVerificationEnabled ? "Active" : "Inactive";
        
        return string(abi.encodePacked(
            'data:application/json;utf8,{',
            '"name":"', property.propertyName, '",',
            '"description":"Digital Property Certificate",',
            '"image":"ipfs://', property.certificatePhotoCID, '",',
            '"attributes":[',
            '{"trait_type":"District/City","value":"', property.district, '"},',
            '{"trait_type":"Total Land Area","value":"', property.totalLandArea.toString(), ' square meters"},',
            '{"trait_type":"Minted Area","value":"', property.mintedLandArea.toString(), ' square meters"},',
            '{"trait_type":"Certificate Type","value":"', property.certificateType, '"},',
            '{"trait_type":"Verification Status","value":"', verifiedStatus, '"},',
            '{"trait_type":"Certificate Number","value":"', property.certificateNumber, '"},',
            '{"trait_type":"Auto Verification","value":"', autoVerifStatus, '"}',
            ']}'
        ));
    }

    // ================== ACCESS CONTROL OVERRIDE ==================
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}