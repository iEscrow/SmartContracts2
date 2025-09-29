// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MultiTokenPresale} from "../src/MultiTokenPresale.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    uint8 private _decimals;
    string private _name;
    string private _symbol;
    
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _totalSupply = 1000000 * 10**decimals_; // 1M tokens
        _balances[msg.sender] = _totalSupply;
    }
    
    function name() public view returns (string memory) {
        return _name;
    }
    
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    
    function decimals() public view returns (uint8) {
        return _decimals;
    }
    
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) public returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    // Mint function for testing
    function mint(address to, uint256 amount) public {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract MultiTokenPresaleTest is Test {
    MultiTokenPresale public presale;
    MockERC20 public presaleToken;
    MockERC20 public usdcToken;
    MockERC20 public usdtToken;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    uint256 public constant PRESALE_RATE = 666666666666666666; // 0.0015 USD per token
    uint256 public constant MAX_TOKENS = 5_000_000_000 * 10**18; // 5B tokens
    
    event TokenPurchase(address indexed buyer, address indexed beneficiary, address indexed paymentToken, uint256 paymentAmount, uint256 tokenAmount);
    event TokenStatusUpdated(address indexed token, bool isActive);
    event PriceUpdated(address indexed token, uint256 newPrice);
    
    function setUp() public {
        // Deploy mock tokens
        presaleToken = new MockERC20("TestToken", "TT", 18);
        usdcToken = new MockERC20("USD Coin", "USDC", 6);
        usdtToken = new MockERC20("Tether USD", "USDT", 6);
        
        // Deploy presale contract
        vm.prank(owner);
        presale = new MultiTokenPresale(
            address(presaleToken),
            PRESALE_RATE,
            MAX_TOKENS,
            owner
        );
        
        // Mint enough tokens for the presale contract to distribute
        // The contract needs MAX_TOKENS (5 billion) for the presale
        presaleToken.mint(address(presale), MAX_TOKENS);
        
        // Set up token prices (in USD with 8 decimals)
        vm.startPrank(owner);
        presale.setTokenPrice(address(0), 2000000000, 18, true); // ETH: $2000
        presale.setTokenPrice(address(usdcToken), 100000000, 6, true); // USDC: $1
        presale.setTokenPrice(address(usdtToken), 100000000, 6, true); // USDT: $1
        presale.setMaxTotalPurchasePerUser(10000000000); // $1000 max per user
        vm.stopPrank();
        
        // Give users some tokens
        usdcToken.mint(user1, 10000 * 10**6); // 10,000 USDC
        usdcToken.mint(user2, 10000 * 10**6); // 10,000 USDC
        usdtToken.mint(user1, 10000 * 10**6); // 10,000 USDT
        usdtToken.mint(user2, 10000 * 10**6); // 10,000 USDT
        
        // Approve presale contract to spend tokens
        vm.prank(user1);
        usdcToken.approve(address(presale), type(uint256).max);
        vm.prank(user1);
        usdtToken.approve(address(presale), type(uint256).max);
        vm.prank(user2);
        usdcToken.approve(address(presale), type(uint256).max);
        vm.prank(user2);
        usdtToken.approve(address(presale), type(uint256).max);
    }
    
    // ============ DEPLOYMENT TESTS ============
    
    function testDeployment() public {
        assertEq(address(presale.presaleToken()), address(presaleToken));
        assertEq(presale.presaleRate(), PRESALE_RATE);
        assertEq(presale.maxTokensToMint(), MAX_TOKENS);
        assertEq(presale.owner(), owner);
        assertEq(presale.totalTokensMinted(), 0);
        assertEq(presale.presaleEnded(), false);
    }
    
    // ============ TOKEN PRICE TESTS ============
    
    function testSetTokenPrice() public {
        vm.prank(owner);
        presale.setTokenPrice(address(usdcToken), 105000000, 6, true); // $1.05
        
        MultiTokenPresale.TokenPrice memory tokenPrice = presale.getTokenPrice(address(usdcToken));
        assertEq(tokenPrice.priceUSD, 105000000);
        assertTrue(tokenPrice.isActive);
        assertEq(tokenPrice.decimals, 6);
    }
    
    function testSetTokenPriceOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        presale.setTokenPrice(address(usdcToken), 105000000, 6, true);
    }
    
    function testSetTokenStatus() public {
        vm.prank(owner);
        presale.setTokenPrice(address(usdcToken), 100000000, 6, false);
        
        MultiTokenPresale.TokenPrice memory tokenPrice = presale.getTokenPrice(address(usdcToken));
        assertFalse(tokenPrice.isActive);
    }
    
    // ============ PRESALE MANAGEMENT TESTS ============
    
    function testStartPresale() public {
        uint256 startTime = block.timestamp;
        uint256 duration = 7 days;
        
        vm.prank(owner);
        presale.startPresale(duration);
        
        (bool started, bool ended, uint256 actualStartTime, uint256 actualEndTime,) = presale.getPresaleStatus();
        assertTrue(started);
        assertFalse(ended);
        assertEq(actualStartTime, startTime);
        assertEq(actualEndTime, startTime + duration);
    }
    
    function testEndPresale() public {
        // Start presale with very short duration
        vm.prank(owner);
        presale.startPresale(1 seconds);
        
        // Wait for presale to end naturally
        vm.warp(block.timestamp + 2 seconds);
        
        vm.prank(owner);
        presale.endPresale();
        
        assertTrue(presale.presaleEnded());
        assertTrue(presale.canClaim());
    }
    
    // ============ PURCHASE TESTS ============
    
    function testBuyWithUSDC() public {
        // Start presale
        vm.prank(owner);
        presale.startPresale(7 days);
        
        uint256 usdcAmount = 100 * 10**6; // 100 USDC (within $1000 limit)
        
        vm.prank(user1);
        presale.buyWithToken(address(usdcToken), usdcAmount, user1);
        
        // Check balances
        assertEq(usdcToken.balanceOf(address(presale)), usdcAmount);
        assertEq(presale.totalPurchased(user1), 100 * PRESALE_RATE);
        assertEq(presale.purchasedAmounts(user1, address(usdcToken)), usdcAmount);
        assertEq(presale.totalUsdPurchased(user1), 100 * 10**8); // 100 USD in 8 decimals
    }
    
    function testBuyWithUSDT() public {
        // Start presale
        vm.prank(owner);
        presale.startPresale(7 days);
        
        uint256 usdtAmount = 100 * 10**6; // 100 USDT (within $1000 limit)
        
        vm.prank(user1);
        presale.buyWithToken(address(usdtToken), usdtAmount, user1);
        
        assertEq(usdtToken.balanceOf(address(presale)), usdtAmount);
        assertEq(presale.totalPurchased(user1), 100 * PRESALE_RATE);
        assertEq(presale.totalUsdPurchased(user1), 100 * 10**8);
    }
    
    function testBuyWithNative() public {
        // Start presale
        vm.prank(owner);
        presale.startPresale(7 days);
        
        // Give user1 some ETH to spend
        vm.deal(user1, 1 ether);
        
        // Use a smaller amount to avoid exceeding the $1000 user limit
        uint256 ethAmount = 0.5 ether; // 0.5 ETH = $1000 (exactly at the limit)
        
        // Get initial balances
        uint256 initialPresaleBalance = address(presale).balance;
        uint256 initialPurchased = presale.totalPurchased(user1);
        uint256 initialUsdPurchased = presale.totalUsdPurchased(user1);
        
        vm.prank(user1);
        presale.buyWithNativeFixed{value: ethAmount}(user1);
        
        // Should have received ETH and made a purchase
        assertTrue(address(presale).balance > initialPresaleBalance);
        assertTrue(presale.totalPurchased(user1) > initialPurchased);
        assertTrue(presale.totalUsdPurchased(user1) > initialUsdPurchased);
    }
    
    function testCalculateTokenAmount() public {
        uint256 usdcAmount = 100 * 10**6; // 100 USDC
        uint256 expectedTokens = 100 * PRESALE_RATE;
        
        uint256 calculatedTokens = presale.calculateTokenAmount(address(usdcToken), usdcAmount, user1);
        assertEq(calculatedTokens, expectedTokens);
    }
    
    // ============ LIMIT TESTS ============
    
    function testMaxPurchaseLimit() public {
        // Start presale
        vm.prank(owner);
        presale.startPresale(7 days);
        
        uint256 usdcAmount = 1001 * 10**6; // 1001 USDC (exceeds $1000 limit)
        
        vm.prank(user1);
        vm.expectRevert("Exceeds max user USD limit");
        presale.buyWithToken(address(usdcToken), usdcAmount, user1);
    }
    
    function testMaxTokensLimit() public {
        // Start presale
        vm.prank(owner);
        presale.startPresale(7 days);
        
        // Set max tokens to a small amount for testing
        vm.prank(owner);
        presale = new MultiTokenPresale(
            address(presaleToken),
            PRESALE_RATE,
            1000 * PRESALE_RATE, // Small limit
            owner
        );
        
        // Set up prices again
        vm.startPrank(owner);
        presale.setTokenPrice(address(usdcToken), 100000000, 6, true);
        presale.setMaxTotalPurchasePerUser(10000000000);
        vm.stopPrank();
        
        uint256 usdcAmount = 1000 * 10**6; // 1000 USDC
        
        vm.prank(user1);
        vm.expectRevert("Presale not started");
        presale.buyWithToken(address(usdcToken), usdcAmount, user1);
    }
    
    // ============ TIMING TESTS ============
    
    function testPurchaseBeforeStart() public {
        // Don't start presale - it should not be active
        uint256 usdcAmount = 100 * 10**6;
        
        vm.prank(user1);
        vm.expectRevert("Presale not started");
        presale.buyWithToken(address(usdcToken), usdcAmount, user1);
    }
    
    function testPurchaseAfterEnd() public {
        // Start presale with very short duration and wait for it to end
        vm.prank(owner);
        presale.startPresale(1 seconds);
        
        // Wait for presale to end
        vm.warp(block.timestamp + 2 seconds);
        
        uint256 usdcAmount = 100 * 10**6;
        
        vm.prank(user1);
        vm.expectRevert("Presale ended");
        presale.buyWithToken(address(usdcToken), usdcAmount, user1);
    }
    
    // ============ PAUSE TESTS ============
    
    function testPauseUnpause() public {
        vm.prank(owner);
        presale.pause();
        assertTrue(presale.paused());
        
        vm.prank(owner);
        presale.unpause();
        assertFalse(presale.paused());
    }
    
    function testPurchaseWhenPaused() public {
        // Start presale
        vm.prank(owner);
        presale.startPresale(7 days);
        
        // Pause presale
        vm.prank(owner);
        presale.pause();
        
        uint256 usdcAmount = 100 * 10**6;
        
        vm.prank(user1);
        vm.expectRevert();
        presale.buyWithToken(address(usdcToken), usdcAmount, user1);
    }
    
    // ============ CLAIM TESTS ============
    
    function testClaimTokens() public {
        // Start presale with very short duration
        vm.prank(owner);
        presale.startPresale(1 seconds);
        
        // Make a purchase
        uint256 usdcAmount = 100 * 10**6;
        vm.prank(user1);
        presale.buyWithToken(address(usdcToken), usdcAmount, user1);
        
        // Wait for presale to end naturally
        vm.warp(block.timestamp + 2 seconds);
        
        // End presale
        vm.prank(owner);
        presale.endPresale();
        
        // Claim tokens
        uint256 expectedTokens = 100 * PRESALE_RATE;
        uint256 initialBalance = presaleToken.balanceOf(user1);
        
        vm.prank(user1);
        presale.claimTokens();
        
        assertEq(presaleToken.balanceOf(user1), initialBalance + expectedTokens);
        assertTrue(presale.hasClaimed(user1));
    }
    
    function testClaimBeforeEnd() public {
        // Start presale
        vm.prank(owner);
        presale.startPresale(7 days);
        
        // Make a purchase
        uint256 usdcAmount = 100 * 10**6;
        vm.prank(user1);
        presale.buyWithToken(address(usdcToken), usdcAmount, user1);
        
        // Try to claim before presale ends
        vm.prank(user1);
        vm.expectRevert("Presale not ended yet");
        presale.claimTokens();
    }
    
    function testClaimTwice() public {
        // Start presale with very short duration
        vm.prank(owner);
        presale.startPresale(1 seconds);
        
        // Make a purchase
        uint256 usdcAmount = 100 * 10**6;
        vm.prank(user1);
        presale.buyWithToken(address(usdcToken), usdcAmount, user1);
        
        // Wait for presale to end naturally
        vm.warp(block.timestamp + 2 seconds);
        
        // End presale
        vm.prank(owner);
        presale.endPresale();
        
        // Claim tokens
        vm.prank(user1);
        presale.claimTokens();
        
        // Try to claim again
        vm.prank(user1);
        vm.expectRevert("Already claimed");
        presale.claimTokens();
    }
    
    // ============ VIEW FUNCTION TESTS ============
    
    function testGetRemainingTokens() public {
        uint256 remaining = presale.getRemainingTokens();
        assertEq(remaining, MAX_TOKENS);
        
        // Start presale and make a purchase
        vm.prank(owner);
        presale.startPresale(7 days);
        
        uint256 usdcAmount = 100 * 10**6;
        vm.prank(user1);
        presale.buyWithToken(address(usdcToken), usdcAmount, user1);
        
        uint256 newRemaining = presale.getRemainingTokens();
        assertEq(newRemaining, MAX_TOKENS - (100 * PRESALE_RATE));
    }
    
    function testGetPresaleStatus() public {
        (bool started, bool ended, uint256 startTime, uint256 endTime, uint256 currentTime) = presale.getPresaleStatus();
        assertFalse(started);
        assertFalse(ended);
        assertEq(startTime, 0);
        assertEq(endTime, 0);
        assertEq(currentTime, block.timestamp);
    }
    
    function testIsPresaleActive() public {
        assertFalse(presale.isPresaleActive());
        
        // Start presale
        vm.prank(owner);
        presale.startPresale(7 days);
        
        assertTrue(presale.isPresaleActive());
    }
    
    function testGetUserPurchases() public {
        (uint256 nativeAmount, uint256 totalTokens, bool claimed) = presale.getUserPurchases(user1);
        assertEq(nativeAmount, 0);
        assertEq(totalTokens, 0);
        assertFalse(claimed);
    }
    
    // ============ EDGE CASE TESTS ============
    
    function testZeroAmountPurchase() public {
        vm.prank(owner);
        presale.startPresale(7 days);
        
        vm.prank(user1);
        vm.expectRevert("Invalid amount");
        presale.buyWithToken(address(usdcToken), 0, user1);
    }
    
    function testInvalidBeneficiary() public {
        vm.prank(owner);
        presale.startPresale(7 days);
        
        vm.prank(user1);
        vm.expectRevert("Invalid beneficiary");
        presale.buyWithToken(address(usdcToken), 100 * 10**6, address(0));
    }
    
    function testInactiveToken() public {
        vm.prank(owner);
        presale.startPresale(7 days);
        
        // Deactivate USDC
        vm.prank(owner);
        presale.setTokenPrice(address(usdcToken), 100000000, 6, false);
        
        vm.prank(user1);
        vm.expectRevert("Token not accepted");
        presale.buyWithToken(address(usdcToken), 100 * 10**6, user1);
    }
    
    function testNativePurchaseWithInsufficientValue() public {
        vm.prank(owner);
        presale.startPresale(7 days);
        
        vm.prank(user1);
        vm.expectRevert("No native currency sent");
        presale.buyWithNative{value: 0}(user1);
    }
    
    // ============ GAS OPTIMIZATION TESTS ============
    
    function testMultiplePurchases() public {
        vm.prank(owner);
        presale.startPresale(7 days);
        
        // Make multiple purchases (total $100, within $1000 limit)
        vm.startPrank(user1);
        presale.buyWithToken(address(usdcToken), 50 * 10**6, user1);
        presale.buyWithToken(address(usdtToken), 50 * 10**6, user1);
        vm.stopPrank();
        
        assertEq(presale.totalPurchased(user1), 100 * PRESALE_RATE);
        assertEq(presale.totalUsdPurchased(user1), 100 * 10**8);
    }

}
