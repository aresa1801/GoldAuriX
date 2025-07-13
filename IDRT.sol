// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title IDRT - Indonesian Rupiah Token
 * @notice 1 IDRT = 1 Indonesian Rupiah (Fixed supply: 100 trillion)
 * @dev Features:
 * - Fixed supply of 100 trillion tokens (100,000,000,000,000 * 10^18)
 * - No minting after deployment
 * - Account freezing for compliance
 * - Circuit breaker pattern
 * - ERC20 compliance with enhanced security
 */
contract IDRT is ERC20, Ownable2Step, Pausable {
    uint256 public constant MAX_SUPPLY = 100_000_000_000_000 * 10**18;
    bool private _initialMintComplete;
    mapping(address => bool) private _frozenAccounts;

    event AccountFrozen(address indexed account);
    event AccountUnfrozen(address indexed account);

    constructor() ERC20("Indonesian Rupiah Token", "IDRT") Ownable(msg.sender) {
        _initialMint();
    }

    // ================ MODIFIERS ================
    modifier notFrozen(address account) {
        require(!_frozenAccounts[account], "IDRT: account frozen");
        _;
    }

    // ================ TRANSFER FUNCTIONS ================
    function transfer(address to, uint256 amount) 
        public 
        override 
        whenNotPaused 
        notFrozen(msg.sender)
        returns (bool) 
    {
        _validateTransfer(msg.sender, to, amount);
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) 
        public 
        override 
        whenNotPaused 
        notFrozen(from)
        returns (bool) 
    {
        _validateTransfer(from, to, amount);
        return super.transferFrom(from, to, amount);
    }

    // ================ SECURITY FEATURES ================
    function freezeAccount(address account) external onlyOwner {
        require(!_frozenAccounts[account], "IDRT: already frozen");
        _frozenAccounts[account] = true;
        emit AccountFrozen(account);
    }

    function unfreezeAccount(address account) external onlyOwner {
        require(_frozenAccounts[account], "IDRT: not frozen");
        _frozenAccounts[account] = false;
        emit AccountUnfrozen(account);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ================ VIEW FUNCTIONS ================
    function isFrozen(address account) external view returns (bool) {
        return _frozenAccounts[account];
    }

    // ================ INTERNAL FUNCTIONS ================
    function _validateTransfer(address from, address to, uint256 amount) internal pure {
        require(to != address(0), "IDRT: transfer to zero address");
        require(amount > 0, "IDRT: zero amount");
        require(from != to, "IDRT: self-transfer");
    }

    // One-time mint during construction
    function _initialMint() internal {
        require(!_initialMintComplete, "IDRT: already minted");
        _mint(owner(), MAX_SUPPLY);
        _initialMintComplete = true;
    }
}