// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract MultiTokenPresale is Ownable, ReentrancyGuard, Pausable {
    
    // Token price structure
    struct TokenPrice {
        uint256 priceUSD;        // Price in USD (8 decimals)
        bool isActive;           // Whether this token is accepted
        uint8 decimals;          // Token decimals
    }
    
    // Presale token details
    IERC20 public presaleToken;
    uint256 public presaleRate;  // Tokens per USD (18 decimals)
    uint256 public maxTokensToMint;
    uint256 public totalTokensMinted;
    
    // Price management
    mapping(address => TokenPrice) public tokenPrices;
    // mapping(address => uint256) public maxPurchasePerToken;
    uint256 public maxTotalPurchasePerUser; // Total USD value limit per user
    
    // User tracking
    mapping(address => mapping(address => uint256)) public purchasedAmounts; // user => token => amount
    mapping(address => uint256) public totalPurchased; // Total tokens purchased by user
    mapping(address => uint256) public totalUsdPurchased; // User's cumulative USD spent (8 decimals)
    mapping(address => bool) public hasClaimed;
    
    // Presale timing controls
    uint256 public presaleStartTime;
    uint256 public presaleEndTime;
    bool public presaleEnded;
    
    // Constants
    address public constant NATIVE_ADDRESS = address(0); // ETH on Ethereum
    uint256 public constant USD_DECIMALS = 8;
    
    // Ethereum Mainnet Token Addresses
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WBNB_ADDRESS = 0x418D75f65a02b3D53B2418FB8E1fe493759c7605;
    address public constant LINK_ADDRESS = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address public constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; 
    address public constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    
    // Events
    event TokenPurchase(
        address indexed purchaser,
        address indexed beneficiary,
        address indexed paymentToken,
        uint256 paymentAmount,
        uint256 tokenAmount
    );
    
    event TokensClaimed(address indexed user, uint256 amount);
    event PriceUpdated(address indexed token, uint256 newPrice);
    event TokenStatusUpdated(address indexed token, bool isActive);
    event PresaleStarted(uint256 startTime, uint256 endTime);
    event PresaleEnded(uint256 endTime);
    
    constructor(
        address _presaleToken,
        uint256 _presaleRate, // 0.0015 dollar per token && presaleRate = 666666666666666666; // 666.666... with 18 decimals
        uint256 _maxTokensToMint, // 5 billion tokens to presale
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_presaleToken != address(0), "Invalid presale token");
        require(_presaleRate > 0, "Invalid presale rate");
        require(_maxTokensToMint > 0, "Invalid max tokens");
        require(_initialOwner != address(0), "Invalid initial owner");
        
        presaleToken = IERC20(_presaleToken);
        presaleRate = _presaleRate;
        maxTokensToMint = _maxTokensToMint;
        
        // Initialize default token prices and limits
        _initializeDefaultTokens();
    }
    
    // Initialize default token settings for UnityFinance presale
    function _initializeDefaultTokens() internal {
        // ETH (Native) - $4200, 18 decimals, per-token cap disabled (use global cap)
        tokenPrices[NATIVE_ADDRESS] = TokenPrice({
            priceUSD: 4200 * 1e8,  // $4200
            isActive: true,
            decimals: 18
        });
        
        // WETH - $4200, 18 decimals, per-token cap disabled (use global cap)
        tokenPrices[WETH_ADDRESS] = TokenPrice({
            priceUSD: 4200 * 1e8,  // $4200
            isActive: true,
            decimals: 18
        });

        // WBNB - $1000, 18 decimals, per-token cap disabled (use global cap)
        tokenPrices[WBNB_ADDRESS] = TokenPrice({
            priceUSD: 1000 * 1e8,   // $1000
            isActive: true,
            decimals: 18
        });
        
        
        // LINK - $20, 18 decimals, per-token cap disabled (use global cap)
        tokenPrices[LINK_ADDRESS] = TokenPrice({
            priceUSD: 20 * 1e8,    // $20
            isActive: true,
            decimals: 18
        });        
        // WBTC - $45000, 8 decimals, per-token cap disabled (use global cap)
        tokenPrices[WBTC_ADDRESS] = TokenPrice({
            priceUSD: 45000 * 1e8, // $45000
            isActive: true,
            decimals: 8
        });
        
        // USDC - $1, 6 decimals, per-token cap disabled (use global cap)
        tokenPrices[USDC_ADDRESS] = TokenPrice({
            priceUSD: 1 * 1e8,     // $1
            isActive: true,
            decimals: 6
        });
        
        // USDT - $1, 6 decimals, per-token cap disabled (use global cap)
        tokenPrices[USDT_ADDRESS] = TokenPrice({
            priceUSD: 1 * 1e8,     // $1
            isActive: true,
            decimals: 6
        });
        
        // Set total USD limit per user to $10,000 (all tokens combined)
        maxTotalPurchasePerUser = 10000 * 1e8; // $10,000 total
        
        // Set gas buffer for Ethereum (0.0005 ETH)
        gasBuffer = 0.0005 ether;
    }
    
    // ============ PRICE MANAGEMENT ============
    
    function setTokenPrice(
        address token,
        uint256 priceUSD,
        uint8 decimals,
        bool isActive
    ) external onlyOwner {
        require(priceUSD > 0, "Invalid price");
        require(decimals <= 18, "Invalid decimals");
        
        tokenPrices[token] = TokenPrice({
            priceUSD: priceUSD,
            isActive: isActive,
            decimals: decimals
        });
        
        emit PriceUpdated(token, priceUSD);
        emit TokenStatusUpdated(token, isActive);
    }
        
    function setMaxTotalPurchasePerUser(uint256 maxUSDValue) external onlyOwner {
        maxTotalPurchasePerUser = maxUSDValue;
    }
    
    // Presale timing controls
    function startPresale(uint256 _duration) external onlyOwner {
        require(presaleStartTime == 0, "Presale already started");
        presaleStartTime = block.timestamp;
        presaleEndTime = block.timestamp + _duration;
        emit PresaleStarted(presaleStartTime, presaleEndTime);
    }
    
    function endPresale() external onlyOwner {
        require(presaleStartTime > 0, "Presale not started");
        require(!presaleEnded, "Presale already ended");
        if(block.timestamp < presaleEndTime) revert("Presale not ended yet");
        presaleEnded = true;
        presaleEndTime = block.timestamp;
        emit PresaleEnded(presaleEndTime);
    }
    
    function extendPresale(uint256 _additionalDuration) external onlyOwner {
        require(presaleStartTime > 0, "Presale not started");
        require(!presaleEnded, "Presale already ended");
        presaleEndTime += _additionalDuration;
    }
    
    // ============ PURCHASE FUNCTIONS ============
    
    // Purchase with native currency (ETH on Ethereum, BNB on BSC)
    function buyWithNative(address beneficiary) external payable nonReentrant whenNotPaused {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(msg.value > 0, "No native currency sent");
        require(presaleStartTime > 0, "Presale not started");
        require(block.timestamp >= presaleStartTime, "Presale not started yet");
        require(block.timestamp <= presaleEndTime, "Presale ended");
        require(!presaleEnded, "Presale ended");
        
        TokenPrice memory nativePrice = tokenPrices[NATIVE_ADDRESS];
        require(nativePrice.isActive, "Native currency not accepted");
        
        // Estimate gas cost and deduct from payment
        uint256 gasCost = _estimateGasCost();
        require(msg.value > gasCost, "Insufficient payment after gas");
        
        uint256 paymentAmount = msg.value - gasCost;
        uint256 tokenAmount = _calculateTokenAmount(NATIVE_ADDRESS, paymentAmount, beneficiary);
        _processPurchase(beneficiary, NATIVE_ADDRESS, paymentAmount, tokenAmount);
    }
    
    // Purchase with ERC20 tokens
    function buyWithToken(
        address token,
        uint256 amount,
        address beneficiary
    ) public nonReentrant whenNotPaused {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(amount > 0, "Invalid amount");
        require(token != NATIVE_ADDRESS, "Use buyWithNative for native currency");
        require(presaleStartTime > 0, "Presale not started");
        require(block.timestamp >= presaleStartTime, "Presale not started yet");
        require(block.timestamp <= presaleEndTime, "Presale ended");
        require(!presaleEnded, "Presale ended");
        require(beneficiary == msg.sender, "Beneficiary must be the same as the sender");
        
        TokenPrice memory tokenPrice = tokenPrices[token];
        require(tokenPrice.isActive, "Token not accepted");
        
        // Check allowance and transfer tokens
        IERC20 tokenContract = IERC20(token);
        tokenContract.transferFrom(msg.sender, address(this), amount);
        
        uint256 tokenAmount = _calculateTokenAmount(token, amount, beneficiary);
        _processPurchase(beneficiary, token, amount, tokenAmount);
    }
    
    // Convenience functions for specific tokens
    function buyWithWETH(uint256 amount, address beneficiary) external {
        buyWithToken(WETH_ADDRESS, amount, beneficiary);
    }
    
    function buyWithWBNB(uint256 amount, address beneficiary) external {
        buyWithToken(WBNB_ADDRESS, amount, beneficiary);
    }
    
    function buyWithLINK(uint256 amount, address beneficiary) external {
        buyWithToken(LINK_ADDRESS, amount, beneficiary);
    }
    
    function buyWithWBTC(uint256 amount, address beneficiary) external {
        buyWithToken(WBTC_ADDRESS, amount, beneficiary);
    }
    
    function buyWithUSDC(uint256 amount, address beneficiary) external {
        buyWithToken(USDC_ADDRESS, amount, beneficiary);
    }
    
    function buyWithUSDT(uint256 amount, address beneficiary) external {
        buyWithToken(USDT_ADDRESS, amount, beneficiary);
    }
    
    // ============ INTERNAL FUNCTIONS ============
    
    function _calculateTokenAmount(address paymentToken, uint256 paymentAmount, address beneficiary) internal view returns (uint256) {
        TokenPrice memory price = tokenPrices[paymentToken];
        require(price.isActive, "Token not accepted");
        
        // Convert payment amount to USD value
        uint256 usdValue = _getUSDValue(paymentToken, paymentAmount);

        // Check if this purchase would exceed the user's limit
        uint256 newTotalUsd = totalUsdPurchased[beneficiary] + usdValue
        require(newTotalUsd <= maxTotalPurchasePerUser, "Exceeds max user USD limit");
        
        // Calculate presale tokens
        return (usdValue * presaleRate) ;
    }
    
    function _updateUserUSDTotal(address beneficiary, uint256 usdValue) internal {
        totalUsdPurchased[beneficiary] += usdValue * 1e8;
    }
    
    function _processPurchase(
        address beneficiary,
        address paymentToken,
        uint256 paymentAmount,
        uint256 tokenAmount
    ) internal {     
        // Check if we can mint enough tokens
        require(totalTokensMinted + tokenAmount <= maxTokensToMint, "Not enough tokens left");
        
        // Calculate USD value and update total
        TokenPrice memory price = tokenPrices[paymentToken];
        uint256 usdValue = (paymentAmount * price.priceUSD) / (10 ** price.decimals * 10 ** USD_DECIMALS);
        _updateUserUSDTotal(beneficiary, usdValue);
        
        // Update tracking
        purchasedAmounts[beneficiary][paymentToken] += paymentAmount;
        totalPurchased[beneficiary] += tokenAmount;
        totalTokensMinted += tokenAmount;
        
        emit TokenPurchase(msg.sender, beneficiary, paymentToken, paymentAmount, tokenAmount);
    }
    
    // ============ CLAIM FUNCTIONS ============
    
    function claimTokens() external nonReentrant {
        require(totalPurchased[msg.sender] > 0, "No tokens to claim");
        require(!hasClaimed[msg.sender], "Already claimed");
        require(presaleEnded, "Presale not ended yet");
        
        uint256 claimAmount = totalPurchased[msg.sender];
        hasClaimed[msg.sender] = true;
        
        require(presaleToken.transfer(msg.sender, claimAmount), "Transfer failed");
        
        emit TokensClaimed(msg.sender, claimAmount);
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    function withdrawNative() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No native currency to withdraw");
        payable(owner()).transfer(balance);
    }
    
    function withdrawToken(address token) external onlyOwner {
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        require(tokenContract.transfer(owner(), balance), "Transfer failed");
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ============ VIEW FUNCTIONS ============
    
    function getTokenPrice(address token) external view returns (TokenPrice memory) {
        return tokenPrices[token];
    }
    
    function getUserPurchases(address user) external view returns (
        uint256 nativeAmount,
        uint256 totalTokens,
        bool claimed
    ) {
        nativeAmount = purchasedAmounts[user][NATIVE_ADDRESS];
        totalTokens = totalPurchased[user];
        claimed = hasClaimed[user];
    }
    
    function calculateTokenAmount(address paymentToken, uint256 paymentAmount, address beneficiary) external view returns (uint256) {
        return _calculateTokenAmount(paymentToken, paymentAmount, beneficiary);
    }
    
    function getRemainingTokens() external view returns (uint256) {
        return maxTokensToMint - totalTokensMinted;
    }
    
    // Presale status functions
    function getPresaleStatus() external view returns (
        bool started,
        bool ended,
        uint256 startTime,
        uint256 endTime,
        uint256 currentTime
    ) {
        started = presaleStartTime > 0;
        ended = presaleEnded;
        startTime = presaleStartTime;
        endTime = presaleEndTime;
        currentTime = block.timestamp;
    }
    
    function isPresaleActive() external view returns (bool) {
        return presaleStartTime > 0 && 
               block.timestamp >= presaleStartTime && 
               block.timestamp <= presaleEndTime && 
               !presaleEnded;
    }
    
    function canClaim() external view returns (bool) {
        return presaleEnded;
    }
    
    // Helper functions for USD value calculations
    function _getUSDValue(address token, uint256 amount) internal view returns (uint256) {
        TokenPrice memory price = tokenPrices[token];
        return (amount * price.priceUSD) / (10 ** price.decimals);
    }
    
    function _getUserTotalUSDValue(address user) internal view returns (uint256) {
        return totalUsdPurchased[user];
    }
    
    function getUserTotalUSDValue(address user) external view returns (uint256) {
        return totalUsdPurchased[user];
    }
    
    // Get all supported tokens information
    function getSupportedTokens() external view returns (
        address[] memory tokens,
        string[] memory symbols,
        uint256[] memory prices,
        uint256[] memory maxPurchases,
        bool[] memory active
    ) {
        tokens = new address[](7);
        symbols = new string[](7);
        prices = new uint256[](7);
        maxPurchases = new uint256[](7);
        active = new bool[](7);
        
        tokens[0] = NATIVE_ADDRESS;
        symbols[0] = "ETH";
        prices[0] = tokenPrices[NATIVE_ADDRESS].priceUSD;
        maxPurchases[0] = maxTotalPurchasePerUser;
        active[0] = tokenPrices[NATIVE_ADDRESS].isActive;
        
        tokens[1] = WETH_ADDRESS;
        symbols[1] = "WETH";
        prices[1] = tokenPrices[WETH_ADDRESS].priceUSD;
        maxPurchases[1] = maxTotalPurchasePerUser;
        active[1] = tokenPrices[WETH_ADDRESS].isActive;
        
        tokens[2] = WBNB_ADDRESS;
        symbols[2] = "WBNB";
        prices[2] = tokenPrices[WBNB_ADDRESS].priceUSD;
        maxPurchases[2] = maxTotalPurchasePerUser;
        active[2] = tokenPrices[WBNB_ADDRESS].isActive;
        
        tokens[3] = LINK_ADDRESS;
        symbols[3] = "LINK";
        prices[3] = tokenPrices[LINK_ADDRESS].priceUSD;
        maxPurchases[3] = maxTotalPurchasePerUser;
        active[3] = tokenPrices[LINK_ADDRESS].isActive;
        
        tokens[4] = WBTC_ADDRESS;
        symbols[4] = "WBTC";
        prices[4] = tokenPrices[WBTC_ADDRESS].priceUSD;
        maxPurchases[4] = maxTotalPurchasePerUser;
        active[4] = tokenPrices[WBTC_ADDRESS].isActive;
        
        tokens[5] = USDC_ADDRESS;
        symbols[5] = "USDC";
        prices[5] = tokenPrices[USDC_ADDRESS].priceUSD;
        maxPurchases[5] = maxTotalPurchasePerUser;
        active[5] = tokenPrices[USDC_ADDRESS].isActive;
        
        tokens[6] = USDT_ADDRESS;
        symbols[6] = "USDT";
        prices[6] = tokenPrices[USDT_ADDRESS].priceUSD;
        maxPurchases[6] = maxTotalPurchasePerUser;
        active[6] = tokenPrices[USDT_ADDRESS].isActive;
    }
    
    // Get user's purchases for all tokens
    function getUserAllPurchases(address user) external view returns (
        uint256[] memory amounts,
        uint256[] memory usdValues
    ) {
        amounts = new uint256[](7);
        usdValues = new uint256[](7);
        
        address[] memory tokens = new address[](7);
        tokens[0] = NATIVE_ADDRESS;
        tokens[1] = WETH_ADDRESS;
        tokens[2] = WBNB_ADDRESS;
        tokens[3] = LINK_ADDRESS;
        tokens[4] = WBTC_ADDRESS;
        tokens[5] = USDC_ADDRESS;
        tokens[6] = USDT_ADDRESS;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = purchasedAmounts[user][tokens[i]];
            if (amounts[i] > 0) {
                usdValues[i] = _getUSDValue(tokens[i], amounts[i]);
            }
        }
    }
    
    // Gas estimation function
    function _estimateGasCost() internal view returns (uint256) {
        // Get current gas price
        uint256 gasPrice = tx.gasprice;
        
        // Estimate gas usage based on operation complexity
        uint256 estimatedGasUsed = _getEstimatedGasUsage();
        
        // Add 20% buffer for safety
        uint256 gasWithBuffer = (estimatedGasUsed * 120) / 100;
        
        return gasPrice * gasWithBuffer;
    }
    
    // Estimate gas usage based on operation
    function _getEstimatedGasUsage() internal pure returns (uint256) {
        // Base gas for contract call
        uint256 baseGas = 21000;
        
        // Gas for storage operations
        uint256 storageGas = 20000; // For updating mappings
        
        // Gas for calculations
        uint256 calculationGas = 10000; // For price calculations
        
        // Gas for events
        uint256 eventGas = 5000; // For emitting events
        
        return baseGas + storageGas + calculationGas + eventGas;
    }
    
    // Alternative: Allow admin to set gas buffer
    uint256 public gasBuffer = 0.01 ether; // Default 0.01 ETH buffer
    
    function setGasBuffer(uint256 _gasBuffer) external onlyOwner {
        gasBuffer = _gasBuffer;
    }
    
    // Alternative implementation with fixed gas buffer
    function buyWithNativeFixed(address beneficiary) external payable nonReentrant whenNotPaused {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(msg.value > gasBuffer, "Insufficient payment after gas buffer");
        
        TokenPrice memory nativePrice = tokenPrices[NATIVE_ADDRESS];
        require(nativePrice.isActive, "Native currency not accepted");
        
        uint256 paymentAmount = msg.value - gasBuffer;
        uint256 tokenAmount = _calculateTokenAmount(NATIVE_ADDRESS, paymentAmount, beneficiary);
        _processPurchase(beneficiary, NATIVE_ADDRESS, paymentAmount, tokenAmount);
    }
}
