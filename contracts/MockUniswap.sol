// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUniswap {

    mapping(address => uint256) public tokenPrices;

    event Swap(
        address indexed sender,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    // USDC 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    // WETH 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    // WBTC 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599

    constructor() {
        tokenPrices[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 1e18;
        tokenPrices[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 3000e18;
        tokenPrices[0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599] = 100000e18;
    }

    modifier isSupportedTokens (address tokenIn, address tokenOut) {
        require(tokenPrices[tokenIn] > 0 && tokenPrices[tokenOut] > 0, "Unsupported token.");
        _;
    }

    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external isSupportedTokens(tokenIn, tokenOut) returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Deadline passed.");

        uint256 amountOut = (amountIn * tokenPrices[tokenIn]) / tokenPrices[tokenOut];

        require(amountOut >= amountOutMin, "Insufficient output amount.");

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view isSupportedTokens(tokenIn, tokenOut) returns (uint256 amountOut) {
        amountOut = (amountIn * tokenPrices[tokenIn]) / tokenPrices[tokenOut];
    }

    function getAmountIn(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view isSupportedTokens(tokenIn, tokenOut) returns (uint256 amountIn) {
        amountIn = (amountOut * tokenPrices[tokenOut]) / tokenPrices[tokenIn];
    }

    function getPrice(address tokenIn, address tokenOut) external view isSupportedTokens(tokenIn, tokenOut) returns (uint256) {

        uint256 price = (tokenPrices[tokenIn] * 1e18) / tokenPrices[tokenOut];

        return price;
    }

}