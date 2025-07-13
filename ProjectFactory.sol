// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface IFarmingProject {
    function initialize(
        address _cooperative,
        uint256 _targetAmount,
        uint256 _fee,
        string calldata _title,
        string calldata _metadataHash
    ) external;
}

contract ProjectFactory is Ownable, Pausable {
    address public immutable idrtToken;
    address public farmingProjectImplementation;
    uint256 public projectFee = 2000 * 10**6;
    uint256 public nextProjectId;
    uint256 public totalFeeCollected;

    mapping(uint256 => address) public projectContracts;
    mapping(address => bool) public isWhitelistedCooperative;
    mapping(address => uint256[]) public cooperativeProjects;

    error ZeroAddress();
    error NotCooperative();
    error DeploymentFailed();
    error InvalidInput();

    event ProjectCreated(uint256 indexed projectId, address projectContract);
    event ProjectFeeUpdated(uint256 newFee);
    event FarmingProjectImplementationUpdated(address newImpl);
    event CooperativeWhitelisted(address indexed coop, bool status);

    constructor(address _idrtToken, address _owner, address _impl) Ownable(_owner) {
        if (_idrtToken == address(0) || _impl == address(0) || _owner == address(0)) revert ZeroAddress();
        idrtToken = _idrtToken;
        farmingProjectImplementation = _impl;
    }

    modifier onlyCooperative() {
        if (!isWhitelistedCooperative[msg.sender]) revert NotCooperative();
        _;
    }

    function setProjectFee(uint256 newFee) external onlyOwner {
        projectFee = newFee;
        emit ProjectFeeUpdated(newFee);
    }

    function setFarmingProjectImplementation(address newImpl) external onlyOwner {
        if (newImpl == address(0)) revert ZeroAddress();
        farmingProjectImplementation = newImpl;
        emit FarmingProjectImplementationUpdated(newImpl);
    }

    function setCooperative(address coop, bool status) external onlyOwner {
        if (coop == address(0)) revert ZeroAddress();
        isWhitelistedCooperative[coop] = status;
        emit CooperativeWhitelisted(coop, status);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function createProject(
        uint256 _targetAmount,
        string calldata _title,
        string calldata _metadataHash
    ) external whenNotPaused onlyCooperative returns (address) {
        if (_targetAmount == 0 || bytes(_title).length == 0 || bytes(_metadataHash).length == 0) revert InvalidInput();

        bytes32 salt = keccak256(abi.encodePacked(nextProjectId, msg.sender, block.number));
        address clone = _deployClone(salt);

        IFarmingProject(clone).initialize(
            msg.sender,
            _targetAmount,
            projectFee,
            _title,
            _metadataHash
        );

        projectContracts[nextProjectId] = clone;
        cooperativeProjects[msg.sender].push(nextProjectId);

        emit ProjectCreated(nextProjectId, clone);
        nextProjectId++;

        return clone;
    }

    function _deployClone(bytes32 salt) internal returns (address proxy) {
        address impl = farmingProjectImplementation;
        bytes20 targetBytes = bytes20(impl);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3)
            mstore(add(clone, 0x14), 0x363d3d373d3d3d363d73)
            mstore(add(clone, 0x28), targetBytes)
            mstore(add(clone, 0x3c), 0x5af43d82803e903d91602b57fd5bf3)
            proxy := create2(0, clone, 0x37, salt)
        }
        if (proxy == address(0)) revert DeploymentFailed();
    }

    function getProjectsByCooperative(address coop) external view returns (uint256[] memory) {
        return cooperativeProjects[coop];
    }

    function getProjectContract(uint256 id) external view returns (address) {
        return projectContracts[id];
    }
} 
