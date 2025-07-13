// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title VaultManager
 * @notice Manajemen cadangan emas fisik untuk GoldToken
 */
contract VaultManager is AccessControl {
    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");
    bytes32 public constant TOKEN_CONTRACT_ROLE = keccak256("TOKEN_CONTRACT_ROLE");

    uint256 public totalReserveGrams;  // Total gram emas di vault fisik
    uint256 public reserveUsed;        // Total gram emas yang sudah dicetak menjadi token

    event ReserveUpdated(uint256 newTotal);
    event ReserveUsedAdded(uint256 amount);
    event ReserveUsedReduced(uint256 amount);

    constructor(address admin) {
        require(admin != address(0), "Invalid admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VAULT_ADMIN_ROLE, admin);
    }

    /**
     * @notice Update jumlah total emas fisik (hanya oleh Vault Admin)
     */
    function setTotalReserve(uint256 grams) external onlyRole(VAULT_ADMIN_ROLE) {
        require(grams >= reserveUsed, "Reserve can't be less than used");
        totalReserveGrams = grams;
        emit ReserveUpdated(grams);
    }

    /**
     * @notice Dipanggil oleh GoldToken saat mint → menambah cadangan yang terpakai
     */
    function addReserveUsed(uint256 amount) external onlyRole(TOKEN_CONTRACT_ROLE) {
        require(reserveUsed + amount <= totalReserveGrams, "Not enough physical reserve");
        reserveUsed += amount;
        emit ReserveUsedAdded(amount);
    }

    /**
     * @notice Dipanggil saat redeem → mengurangi cadangan yang terpakai
     */
    function reduceReserveUsed(uint256 amount) external onlyRole(TOKEN_CONTRACT_ROLE) {
        require(amount <= reserveUsed, "Cannot reduce more than used");
        reserveUsed -= amount;
        emit ReserveUsedReduced(amount);
    }

    /**
     * @notice Lihat sisa cadangan emas fisik yang tersedia
     */
    function availableGrams() external view returns (uint256) {
        return totalReserveGrams - reserveUsed;
    }
}
