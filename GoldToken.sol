// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title VaultManager Interface
 * @dev Interface kontrak untuk mengecek dan mengatur cadangan emas fisik
 */
interface IVaultManager {
    function availableGrams() external view returns (uint256);
    function reserveUsed() external view returns (uint256);
    function addReserveUsed(uint256 amount) external;
    function reduceReserveUsed(uint256 amount) external;
}

/**
 * @title Aurix Gold Token (GOLD)
 * @notice ERC20 token yang 100% dijamin emas fisik
 * @dev Gunakan bersama VaultManager untuk kontrol cadangan
 */
contract GoldToken is ERC20Pausable, AccessControl {
    // Role yang diatur
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Referensi ke kontrak VaultManager
    IVaultManager public vault;

    /**
     * @dev Konstruktor, hanya dipanggil saat deploy
     * @param vaultManagerAddress alamat kontrak VaultManager
     * @param admin alamat admin utama
     */
    constructor(address vaultManagerAddress, address admin)
        ERC20("Aurix Gold Token", "GOLD")
    {
        require(vaultManagerAddress != address(0), "Invalid vault address");
        require(admin != address(0), "Invalid admin");

        vault = IVaultManager(vaultManagerAddress);

        // Atur role akses
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    /**
     * @notice Mint token sesuai jumlah emas yang tersedia
     * @dev Hanya SwapRouter atau role yang diizinkan yang bisa mint
     */
    function mint(address to, uint256 amount)
        external
        onlyRole(MINTER_ROLE)
        whenNotPaused
    {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be > 0");
        require(vault.availableGrams() >= amount, "Not enough gold");

        vault.addReserveUsed(amount);
        _mint(to, amount);
    }

    /**
     * @notice Burn token dari user saat redeem emas
     * @dev Digunakan oleh RedeemManager (yang diberi MINTER_ROLE)
     */
    function burnFromVault(address from, uint256 amount)
        external
        onlyRole(MINTER_ROLE)
        whenNotPaused
    {
        require(from != address(0), "Invalid address");
        require(balanceOf(from) >= amount, "Insufficient balance");

        vault.reduceReserveUsed(amount);
        _burn(from, amount);
    }

    /**
     * @notice Pause seluruh aktivitas token (mint, burn, transfer)
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause aktivitas
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
