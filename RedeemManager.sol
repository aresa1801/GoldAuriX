// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./GoldToken.sol"; // Pastikan path ini sesuai lokasi GoldToken.sol

contract RedeemManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    enum RedeemStatus { Pending, Approved, Canceled }

    struct RedeemRequest {
        address user;
        uint256 amount;        // jumlah G-Token (gram)
        uint256 timestamp;
        uint256 fee;           // biaya dalam stablecoin (mis. IDRX)
        RedeemStatus status;
    }

    IERC20 public goldToken;               // untuk transfer & approve
    GoldToken public goldTokenContract;    // untuk burnFromVault()
    IERC20 public stableToken;
    address public feeCollector;

    uint256 public nextRequestId;
    uint256 public minGram = 1e17;         // 0.1 gram
    uint256 public redeemFeeBps = 200;     // 2% = 200 basis point
    uint256 public goldPriceInStable;      // contoh: 1 gram = 1,200,000 IDRX

    mapping(uint256 => RedeemRequest) public redeemRequests;
    mapping(address => uint256[]) public userRedeemHistory;

    event RedeemRequested(uint256 indexed requestId, address indexed user, uint256 amount, uint256 fee);
    event RedeemApproved(uint256 indexed requestId);
    event RedeemCanceled(uint256 indexed requestId);
    event FeeCollectorChanged(address newCollector);
    event GoldPriceUpdated(uint256 newPrice);

    constructor(
        address _goldToken,
        address _stableToken,
        address _admin,
        address _feeCollector
    ) {
        require(_goldToken != address(0), "Invalid token");
        require(_stableToken != address(0), "Invalid stable");
        require(_admin != address(0), "Invalid admin");
        require(_feeCollector != address(0), "Invalid fee collector");

        goldToken = IERC20(_goldToken);
        goldTokenContract = GoldToken(_goldToken);
        stableToken = IERC20(_stableToken);
        feeCollector = _feeCollector;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // Set harga 1 gram emas (misal dalam IDRX smallest unit)
    function setGoldPrice(uint256 newPrice) external onlyRole(ADMIN_ROLE) {
        require(newPrice > 0, "Invalid price");
        goldPriceInStable = newPrice;
        emit GoldPriceUpdated(newPrice);
    }

    // Ubah wallet penampung fee
    function setFeeCollector(address newCollector) external onlyRole(ADMIN_ROLE) {
        require(newCollector != address(0), "Invalid address");
        feeCollector = newCollector;
        emit FeeCollectorChanged(newCollector);
    }

    // Request penukaran G-Token ke fisik emas
    function requestRedeem(uint256 amount) external nonReentrant {
        require(amount >= minGram, "Min redeem is 0.1 gram");
        require(goldToken.balanceOf(msg.sender) >= amount, "Insufficient balance");

        uint256 feeInStable = (amount * goldPriceInStable * redeemFeeBps) / 1e18 / 10000;
        require(stableToken.balanceOf(msg.sender) >= feeInStable, "Insufficient stable balance");

        // Transfer G-Token ke kontrak
        goldToken.safeTransferFrom(msg.sender, address(this), amount);

        // Transfer stable fee ke fee collector
        stableToken.safeTransferFrom(msg.sender, feeCollector, feeInStable);

        redeemRequests[nextRequestId] = RedeemRequest({
            user: msg.sender,
            amount: amount,
            timestamp: block.timestamp,
            fee: feeInStable,
            status: RedeemStatus.Pending
        });

        userRedeemHistory[msg.sender].push(nextRequestId);
        emit RedeemRequested(nextRequestId, msg.sender, amount, feeInStable);
        nextRequestId++;
    }

    // Admin menyetujui permintaan dan membakar token
    function approveRedeem(uint256 requestId) external onlyRole(ADMIN_ROLE) nonReentrant {
        RedeemRequest storage req = redeemRequests[requestId];
        require(req.status == RedeemStatus.Pending, "Invalid status");

        req.status = RedeemStatus.Approved;

        // Burn token dari vault
        goldTokenContract.burnFromVault(address(this), req.amount);

        emit RedeemApproved(requestId);
    }

    // User dapat membatalkan permintaan jika masih pending
    function cancelRedeem(uint256 requestId) external nonReentrant {
        RedeemRequest storage req = redeemRequests[requestId];
        require(req.user == msg.sender, "Not your request");
        require(req.status == RedeemStatus.Pending, "Cannot cancel");

        uint256 refundAmount = req.amount;
        req.status = RedeemStatus.Canceled;
        req.amount = 0;

        goldToken.safeTransfer(msg.sender, refundAmount);
        emit RedeemCanceled(requestId);
    }

    // Melihat semua permintaan user
    function getUserRequests(address user) external view returns (uint256[] memory) {
        return userRedeemHistory[user];
    }

    // Melihat detail permintaan berdasarkan ID
    function getRequest(uint256 id) external view returns (
        address user,
        uint256 amount,
        uint256 timestamp,
        uint256 fee,
        RedeemStatus status
    ) {
        RedeemRequest storage r = redeemRequests[id];
        return (r.user, r.amount, r.timestamp, r.fee, r.status);
    }
}
