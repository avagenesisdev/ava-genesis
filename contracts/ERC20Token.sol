// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title ERC20Token
 * @notice Cloneable ERC-20 template for TokenForge.
 *
 * ALLOCATION AT INIT
 * ──────────────────
 * Factory calls initialize() with:
 *   - ownerSupply  → minted directly to token creator (97%)
 *   - platformAddr + platformSupply → minted to TokenForge treasury (3%)
 *
 * FEATURES (all opt-in via TokenConfig)
 * ──────────────────────────────────────
 * - Mintable     (owner can mint more)
 * - Burnable     (always available — no flag needed)
 * - Pausable     (owner can freeze all transfers)
 * - Buy/Sell Tax (up to 25% each, paid to taxTreasury)
 * - Max Wallet   (anti-whale, % of total supply)
 * - Blacklist    (owner can block addresses)
 */
contract ERC20Token is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    Ownable2StepUpgradeable
{
    uint256 public constant MAX_TAX_BPS = 2500;       // 25%
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ─────────────────────────────────────────────
    // Token config
    // ─────────────────────────────────────────────

    struct TokenConfig {
        bool mintable;
        bool pausable;
        bool blacklistEnabled;
        uint256 maxWalletBps;    // 0 = disabled
        uint256 buyTaxBps;       // 0 = no tax
        uint256 sellTaxBps;      // 0 = no tax
        address taxTreasury;     // where tax goes (defaults to owner)
    }

    TokenConfig public config;
    uint8 private _decimals;

    /// @notice Addresses blocked from sending/receiving (if blacklistEnabled)
    mapping(address => bool) public isBlacklisted;

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    event Minted(address indexed to, uint256 amount);
    event TaxUpdated(uint256 buyBps, uint256 sellBps, address treasury);
    event MaxWalletUpdated(uint256 bps);
    event Blacklisted(address indexed account, bool status);

    // ─────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────

    error NotMintable();
    error NotPausable();
    error BlacklistDisabled();
    error AccountBlacklisted(address account);
    error TaxTooHigh();
    error MaxWalletExceeded();
    error ZeroAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    // ─────────────────────────────────────────────
    // Initialize (called by factory after clone)
    // ─────────────────────────────────────────────

    /**
     * @param name_           Token name
     * @param symbol_         Token symbol
     * @param decimals_       Decimals (18 standard)
     * @param ownerSupply     Amount minted to creator (97% of total)
     * @param owner_          Creator wallet address
     * @param config_         Feature config
     * @param platformAddr    TokenForge treasury address
     * @param platformSupply  Amount minted to treasury (3% of total)
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 ownerSupply,
        address owner_,
        TokenConfig memory config_,
        address platformAddr,
        uint256 platformSupply
    ) external initializer {
        require(bytes(name_).length > 0,   "empty name");
        require(bytes(symbol_).length > 0, "empty symbol");
        require(owner_ != address(0),      "zero owner");
        require(ownerSupply > 0,           "zero supply");
        require(config_.buyTaxBps  <= MAX_TAX_BPS, "buy tax too high");
        require(config_.sellTaxBps <= MAX_TAX_BPS, "sell tax too high");
        require(config_.maxWalletBps <= BPS_DENOMINATOR, "max wallet > 100%");

        __ERC20_init(name_, symbol_);
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __Ownable2Step_init();
        _transferOwnership(owner_);

        _decimals = decimals_;
        config = config_;

        if (config.taxTreasury == address(0)) {
            config.taxTreasury = owner_;
        }

        // Mint 97% to creator
        _mint(owner_, ownerSupply);

        // Mint 3% to platform treasury (if any)
        if (platformSupply > 0 && platformAddr != address(0)) {
            _mint(platformAddr, platformSupply);
        }
    }

    // ─────────────────────────────────────────────
    // Owner functions
    // ─────────────────────────────────────────────

    function mint(address to, uint256 amount) external onlyOwner {
        if (!config.mintable) revert NotMintable();
        _mint(to, amount);
        emit Minted(to, amount);
    }

    function pause() external onlyOwner {
        if (!config.pausable) revert NotPausable();
        _pause();
    }

    function unpause() external onlyOwner {
        if (!config.pausable) revert NotPausable();
        _unpause();
    }

    function setBlacklist(address account, bool status) external onlyOwner {
        if (!config.blacklistEnabled) revert BlacklistDisabled();
        isBlacklisted[account] = status;
        emit Blacklisted(account, status);
    }

    function setTax(uint256 buyBps, uint256 sellBps, address taxTreasury_) external onlyOwner {
        if (buyBps > MAX_TAX_BPS || sellBps > MAX_TAX_BPS) revert TaxTooHigh();
        if (taxTreasury_ == address(0)) revert ZeroAddress();
        config.buyTaxBps = buyBps;
        config.sellTaxBps = sellBps;
        config.taxTreasury = taxTreasury_;
        emit TaxUpdated(buyBps, sellBps, taxTreasury_);
    }

    function setMaxWallet(uint256 bps) external onlyOwner {
        require(bps <= BPS_DENOMINATOR, "max wallet > 100%");
        config.maxWalletBps = bps;
        emit MaxWalletUpdated(bps);
    }

    // ─────────────────────────────────────────────
    // Transfer hook
    // ─────────────────────────────────────────────

    function _update(address from, address to, uint256 value)
        internal override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        // Blacklist check
        if (config.blacklistEnabled) {
            if (from != address(0) && isBlacklisted[from]) revert AccountBlacklisted(from);
            if (to   != address(0) && isBlacklisted[to])   revert AccountBlacklisted(to);
        }

        // Tax (only on real transfers, not mint/burn)
        if (from != address(0) && to != address(0) && value > 0) {
            // Determine tax direction:
            // buyTax  = tokens arriving at non-exempt wallet (simplified: non-from-self)
            // sellTax = tokens leaving owner/uniswap — keep simple: use sellTax on all transfers
            // A real DEX integration would check if from/to is a pair — for now both use buyTax
            uint256 taxBps = config.buyTaxBps;
            if (taxBps > 0 && config.taxTreasury != address(0)) {
                uint256 taxAmt = (value * taxBps) / BPS_DENOMINATOR;
                if (taxAmt > 0) {
                    super._update(from, config.taxTreasury, taxAmt);
                    value -= taxAmt;
                }
            }

            // Max wallet (exclude owner and tax treasury)
            if (config.maxWalletBps > 0 && to != owner() && to != config.taxTreasury) {
                uint256 maxWallet = (totalSupply() * config.maxWalletBps) / BPS_DENOMINATOR;
                if (balanceOf(to) + value > maxWallet) revert MaxWalletExceeded();
            }
        }

        super._update(from, to, value);
    }

    // ─────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────

    function decimals() public view override returns (uint8) { return _decimals; }
    function getConfig() external view returns (TokenConfig memory) { return config; }

    function maxWalletAmount() external view returns (uint256) {
        if (config.maxWalletBps == 0) return 0;
        return (totalSupply() * config.maxWalletBps) / BPS_DENOMINATOR;
    }
}
