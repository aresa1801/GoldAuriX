// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./GoldToken.sol";        // Pastikan path ini sesuai
import "./VaultManager.sol";     // Pastikan path ini sesuai

contract SwapRouter is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IERC20 public stableToken;              // e.g. IDRX
    GoldToken public goldToken;             // Gunakan kontrak asli, bukan interface
    VaultManager public vault;              // Gunakan kontrak asli juga

    uint256 public swapFeePercent = 200;    // 2% fee (in basis points)
    address public feeCollector;

    event SwappedToGold(address indexed user, uint256 stableIn, uint256 goldOut);
    event SwappedToStable(address indexed user, uint256 goldIn, uint256 stableOut);
    event FeeCollectorUpdated(address newCollector);
    event FeePercentUpdated(uint256 newPercent);

    constructor(
        address _stableToken,
        address _goldToken,
        address _vaultManager,
        address _admin,
        address _feeCollector
    ) {
        require(_stableToken != address(0), "Invalid stable token");
        require(_goldToken != address(0), "Invalid gold token");
        require(_vaultManager != address(0), "Invalid vault manager");
        require(_admin != address(0), "Invalid admin");
        require(_feeCollector != address(0), "Invalid fee collector");

        stableToken = IERC20(_stableToken);
        goldToken = GoldToken(_goldToken);
        vault = VaultManager(_vaultManager);
        feeCollector = _feeCollector;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    /**
     * @notice Swap stablecoin ke G-TOKEN berbasis gram emas
     */
    function swapStableToGold(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(vault.availableGrams() >= amount, "Not enough physical gold reserve");

        // Hitung fee 2%
        uint256 fee = (amount * swapFeePercent) / 10000;
        uint256 netAmount = amount - fee;

        // Transfer stablecoin dari user ke kontrak
        stableToken.safeTransferFrom(msg.sender, address(this), amount);

        // Transfer fee ke fee collector
        if (fee > 0) {
            stableToken.safeTransfer(feeCollector, fee);
        }

        // Mint G-TOKEN ke user
        goldToken.mint(msg.sender, netAmount);

        emit SwappedToGold(msg.sender, amount, netAmount);
    }

    /**
     * @notice Swap G-TOKEN kembali ke stablecoin (redeem ke treasury)
     */
    function swapGoldToStable(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(stableToken.balanceOf(address(this)) >= amount, "Insufficient stable liquidity");

        // Hitung fee 2%
        uint256 fee = (amount * swapFeePercent) / 10000;
        uint256 netStable = amount - fee;

        // Burn G-TOKEN dari user
        goldToken.burnFromVault(msg.sender, amount);

        // Transfer stablecoin ke user
        stableToken.safeTransfer(msg.sender, netStable);

        // Transfer fee ke fee collector
        if (fee > 0) {
            stableToken.safeTransfer(feeCollector, fee);
        }

        emit SwappedToStable(msg.sender, amount, netStable);
    }

    /**
     * @notice Update fee collector wallet
     */
    function updateFeeCollector(address newCollector) external onlyRole(ADMIN_ROLE) {
        require(newCollector != address(0), "Invalid address");
        feeCollector = newCollector;
        emit FeeCollectorUpdated(newCollector);
    }

    /**
     * @notice Update persentase fee swap
     */
    function updateFeePercent(uint256 newPercent) external onlyRole(ADMIN_ROLE) {
        require(newPercent <= 500, "Max 5% allowed");
        swapFeePercent = newPercent;
        emit FeePercentUpdated(newPercent);
    }
}
