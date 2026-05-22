// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ERC20Token.sol";

/**
 * @title TokenFactory
 * @notice TokenForge platform factory — 3-tier pricing.
 *
 * PRICING
 * ───────
 * • Starter  ($10):  Standard ERC-20 + burnable, no extra features
 * • Basic    ($20):  Starter + anti-whale (maxWallet limit)
 * • Premium  ($50):  Any of: mintable, pausable, blacklist, buy/sell tax
 *
 * FEE FLOW
 * ────────
 * Every fee is sent DIRECTLY to the treasury wallet at deploy time.
 * No accumulation in the contract — your wallet gets paid instantly.
 * ETH:  msg.value forwarded to treasury, excess refunded to creator.
 * USDC: transferFrom(creator → treasury) in the same transaction.
 *
 * ALLOCATION
 * ──────────
 * 3% of every token's initial supply is minted to the platform treasury.
 * 97% is minted to the token creator.
 */
contract TokenFactory is Ownable2Step, ReentrancyGuard {
    using Clones for address;
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────
    // Tier enum
    // ─────────────────────────────────────────────

    enum Tier { Starter, Basic, Premium }

    // ─────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────

    uint256 public constant PLATFORM_ALLOCATION_BPS = 300;   // 3%
    uint256 public constant BPS_DENOMINATOR         = 10_000;

    // ─────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────

    /// @notice ERC20Token implementation cloned per deployment (EIP-1167)
    address public immutable implementation;

    /// @notice All fees (ETH + USDC) and 3% token allocation go here
    address public treasury;

    // ETH fees per tier (wei) — update via setEthFees() as ETH price changes
    uint256 public starterFeeEth;
    uint256 public basicFeeEth;
    uint256 public premiumFeeEth;

    /// @notice USDC contract on this chain (address(0) = USDC disabled)
    address public usdcAddress;

    // USDC fees per tier (6 decimals: 10_000_000 = $10)
    uint256 public starterFeeUsdc;
    uint256 public basicFeeUsdc;
    uint256 public premiumFeeUsdc;

    /// @notice Running count of all deployed tokens
    uint256 public totalDeployed;

    /// @notice All token addresses in deploy order
    address[] public allTokens;

    /// @notice Tokens deployed by each creator
    mapping(address => address[]) public tokensByOwner;

    /// @notice Quick membership check — was this token made by TokenForge?
    mapping(address => bool) public isTokenForgeToken;

    /// @notice On-chain metadata for every token (used by the explorer)
    struct TokenMeta {
        address owner;
        string  name;
        string  symbol;
        uint256 deployedAt;
        Tier    tier;
    }
    mapping(address => TokenMeta) public tokenMeta;

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    event TokenCreated(
        address indexed token,
        address indexed owner,
        string  name,
        string  symbol,
        uint256 initialSupply,
        uint256 platformAllocation,
        uint8   tier,           // 0=Starter 1=Basic 2=Premium
        uint256 timestamp
    );

    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event EthFeesUpdated(uint256 starter, uint256 basic, uint256 premium);
    event UsdcFeesUpdated(uint256 starter, uint256 basic, uint256 premium);
    event UsdcAddressUpdated(address newUsdc);
    // Safety drain — for any ETH accidentally sent directly to the contract
    event EmergencyEthDrained(address to, uint256 amount);

    // ─────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────

    error InsufficientEthFee(uint256 required, uint256 provided);
    error InsufficientUsdcAllowance(uint256 required, uint256 allowance);
    error UsdcNotSupported();
    error InvalidPaymentToken();
    error ZeroAddress();
    error TreasuryTransferFailed();
    error RefundFailed();
    error NothingToWithdraw();

    // ─────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────

    /**
     * @param implementation_  Deployed ERC20Token template
     * @param treasury_        Your wallet — receives all fees instantly
     * @param starterFeeEth_   ETH price for Starter tier (~$10 in wei)
     * @param basicFeeEth_     ETH price for Basic tier (~$20 in wei)
     * @param premiumFeeEth_   ETH price for Premium tier (~$50 in wei)
     * @param usdcAddress_     USDC on this chain (address(0) to disable)
     * @param starterFeeUsdc_  USDC price Starter (6 dec, e.g. 10_000_000 = $10)
     * @param basicFeeUsdc_    USDC price Basic (e.g. 20_000_000 = $20)
     * @param premiumFeeUsdc_  USDC price Premium (e.g. 50_000_000 = $50)
     */
    constructor(
        address implementation_,
        address treasury_,
        uint256 starterFeeEth_,
        uint256 basicFeeEth_,
        uint256 premiumFeeEth_,
        address usdcAddress_,
        uint256 starterFeeUsdc_,
        uint256 basicFeeUsdc_,
        uint256 premiumFeeUsdc_
    ) Ownable(msg.sender) {
        if (implementation_ == address(0)) revert ZeroAddress();
        if (treasury_       == address(0)) revert ZeroAddress();

        implementation  = implementation_;
        treasury        = treasury_;
        starterFeeEth   = starterFeeEth_;
        basicFeeEth     = basicFeeEth_;
        premiumFeeEth   = premiumFeeEth_;
        usdcAddress     = usdcAddress_;
        starterFeeUsdc  = starterFeeUsdc_;
        basicFeeUsdc    = basicFeeUsdc_;
        premiumFeeUsdc  = premiumFeeUsdc_;
    }

    // ─────────────────────────────────────────────
    // Core — Create Token
    // ─────────────────────────────────────────────

    /**
     * @notice Deploy a new ERC-20 token. Fee is sent DIRECTLY to treasury.
     *
     * @param name          Token name (e.g. "My Protocol Token")
     * @param symbol        Token symbol (e.g. "MPT")
     * @param decimals_     Decimals — 18 is standard
     * @param initialSupply Total supply in smallest unit (min 100)
     * @param config        Feature flags (determines tier + fee)
     * @param paymentToken  address(0) = pay ETH  |  USDC address = pay USDC
     */
    function createToken(
        string calldata name,
        string calldata symbol,
        uint8  decimals_,
        uint256 initialSupply,
        ERC20Token.TokenConfig calldata config,
        address paymentToken
    ) external payable nonReentrant returns (address token) {
        require(initialSupply >= 100, "TokenFactory: supply too small");

        Tier tier = _getTier(config);

        // ── Collect fee → treasury ──────────────────────────────────────
        if (paymentToken == address(0)) {
            // ETH payment: forward fee to treasury, refund any excess
            uint256 required = _ethFee(tier);
            if (msg.value < required) revert InsufficientEthFee(required, msg.value);

            // Send fee directly to treasury wallet
            (bool feeOk,) = payable(treasury).call{value: required}("");
            if (!feeOk) revert TreasuryTransferFailed();

            // Refund overpayment
            uint256 excess = msg.value - required;
            if (excess > 0) {
                (bool refundOk,) = payable(msg.sender).call{value: excess}("");
                if (!refundOk) revert RefundFailed();
            }

        } else if (paymentToken == usdcAddress && usdcAddress != address(0)) {
            // USDC payment: pull from creator directly into treasury
            uint256 required  = _usdcFee(tier);
            uint256 allowance = IERC20(usdcAddress).allowance(msg.sender, address(this));
            if (allowance < required) revert InsufficientUsdcAllowance(required, allowance);

            // Transfer USDC creator → treasury in one step
            IERC20(usdcAddress).safeTransferFrom(msg.sender, treasury, required);

        } else {
            revert InvalidPaymentToken();
        }

        // ── Platform token allocation ────────────────────────────────────
        // Starter ($10): 3% of supply minted to treasury — creator gets 97%
        // Basic ($20) / Premium ($50): pay higher cash fees, creator keeps 100%
        uint256 platformAmount = (tier == Tier.Starter)
            ? (initialSupply * PLATFORM_ALLOCATION_BPS) / BPS_DENOMINATOR
            : 0;
        uint256 ownerAmount = initialSupply - platformAmount;

        // ── Clone + initialise ──────────────────────────────────────────
        token = implementation.clone();
        ERC20Token(token).initialize(
            name,
            symbol,
            decimals_,
            ownerAmount,
            msg.sender,
            config,
            treasury,
            platformAmount
        );

        // ── Track ───────────────────────────────────────────────────────
        totalDeployed++;
        allTokens.push(token);
        tokensByOwner[msg.sender].push(token);
        isTokenForgeToken[token] = true;
        tokenMeta[token] = TokenMeta({
            owner:      msg.sender,
            name:       name,
            symbol:     symbol,
            deployedAt: block.timestamp,
            tier:       tier
        });

        emit TokenCreated(
            token,
            msg.sender,
            name,
            symbol,
            initialSupply,
            platformAmount,
            uint8(tier),
            block.timestamp
        );
    }

    // ─────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────

    function _getTier(ERC20Token.TokenConfig calldata config) internal pure returns (Tier) {
        if (
            config.mintable         ||
            config.pausable         ||
            config.blacklistEnabled ||
            config.buyTaxBps  > 0  ||
            config.sellTaxBps > 0
        ) return Tier.Premium;

        if (config.maxWalletBps > 0) return Tier.Basic;

        return Tier.Starter;
    }

    function _ethFee(Tier tier) internal view returns (uint256) {
        if (tier == Tier.Premium) return premiumFeeEth;
        if (tier == Tier.Basic)   return basicFeeEth;
        return starterFeeEth;
    }

    function _usdcFee(Tier tier) internal view returns (uint256) {
        if (tier == Tier.Premium) return premiumFeeUsdc;
        if (tier == Tier.Basic)   return basicFeeUsdc;
        return starterFeeUsdc;
    }

    // ─────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────

    /**
     * @notice Required fee for a given tier.
     * @param tier    0=Starter 1=Basic 2=Premium
     * @param inUsdc  true → USDC amount (6 dec) | false → ETH in wei
     */
    function getRequiredFee(uint8 tier, bool inUsdc) external view returns (uint256) {
        Tier t = Tier(tier);
        return inUsdc ? _usdcFee(t) : _ethFee(t);
    }

    function getTier(ERC20Token.TokenConfig calldata config) external pure returns (uint8) {
        return uint8(_getTier(config));
    }

    function getTokensByOwner(address owner) external view returns (address[] memory) {
        return tokensByOwner[owner];
    }

    function getTokens(uint256 offset, uint256 limit)
        external view returns (address[] memory tokens, uint256 total)
    {
        total = allTokens.length;
        if (offset >= total) return (new address[](0), total);
        uint256 end = offset + limit > total ? total : offset + limit;
        tokens = new address[](end - offset);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = allTokens[offset + i];
        }
    }

    // ─────────────────────────────────────────────
    // Owner admin — update fees / treasury
    // ─────────────────────────────────────────────

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    function setEthFees(uint256 starter, uint256 basic, uint256 premium) external onlyOwner {
        starterFeeEth = starter;
        basicFeeEth   = basic;
        premiumFeeEth = premium;
        emit EthFeesUpdated(starter, basic, premium);
    }

    function setUsdcFees(uint256 starter, uint256 basic, uint256 premium) external onlyOwner {
        starterFeeUsdc = starter;
        basicFeeUsdc   = basic;
        premiumFeeUsdc = premium;
        emit UsdcFeesUpdated(starter, basic, premium);
    }

    function setUsdcAddress(address newUsdc) external onlyOwner {
        usdcAddress = newUsdc;
        emit UsdcAddressUpdated(newUsdc);
    }

    // ─────────────────────────────────────────────
    // Safety drain — rescue accidentally sent ETH
    // (normal fee flow never leaves ETH here)
    // ─────────────────────────────────────────────

    function drainEth() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        if (bal == 0) revert NothingToWithdraw();
        (bool ok,) = payable(treasury).call{value: bal}("");
        if (!ok) revert TreasuryTransferFailed();
        emit EmergencyEthDrained(treasury, bal);
    }

    /// @notice Accept direct ETH sends (e.g. test scenarios)
    receive() external payable {}
}
