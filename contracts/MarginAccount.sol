// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./LiquidityPool.sol";
import "./MockUniswap.sol";

contract MarginAccount is Ownable {
    struct Account {
        mapping(IERC20 => uint256) collateral;
        mapping(IERC20 => uint256) debt;
    }

    mapping(address => Account) private accounts;
    mapping(IERC20 => LiquidityPool) public tokenToPool;

    address[] public supportedTokens;

    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    MockUniswap public mockUniswap;

    event CollateralDeposited(address indexed trader, IERC20 token, uint256 amount);
    event CollateralWithdrawn(address indexed trader, IERC20 token, uint256 amount);
    event Borrowed(address indexed trader, IERC20 token, uint256 amount);
    event Repaid(address indexed trader, IERC20 token, uint256 amount);
    event Liquidated(address indexed trader);

    // USDC 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    // WETH 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    // WBTC 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599

    constructor(address[] memory _tokens, address[] memory _pools, address _mockUniswap) Ownable(msg.sender) {
        require(_tokens.length == _pools.length, "Mismatched tokens and pools.");
        require(_mockUniswap != address(0), "Invalid address");

        for (uint256 i = 0; i < _tokens.length; i++) {
            require(_tokens[i] != address(0), "Invalid token address");
            require(_pools[i] != address(0), "Invalid pool address");
        }

        supportedTokens = _tokens;
        mockUniswap = MockUniswap(_mockUniswap);

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            tokenToPool[IERC20(_tokens[i])] = LiquidityPool(_pools[i]);
        }
    }

    function getAccountDetails(address trader, IERC20 token) external view returns (uint256 collateral, uint256 debt) {
        collateral = accounts[trader].collateral[token];
        debt = accounts[trader].debt[token];
    }

    function depositCollateral(IERC20 token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0.");
        require(isSupportedToken(address(token)), "Token not supported.");

        require(token.transferFrom(msg.sender, address(this), amount), "Token transfer failed.");

        accounts[msg.sender].collateral[token] += amount;

        emit CollateralDeposited(msg.sender, token, amount);
    }

    function addAcc(address _address, IERC20 token, uint256 Col, uint256 _Debt) public {
        accounts[_address].collateral[token] = Col;
        accounts[_address].debt[token] = _Debt;
    }

    function withdrawCollateral(IERC20 token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0.");
        require(accounts[msg.sender].collateral[token] >= amount, "Insufficient collateral.");

        uint256 totalCollateralValue = getTotalCollateralValue(msg.sender);
        uint256 totalDebtValue = getTotalDebtValue(msg.sender);

        require((totalCollateralValue * 100) / totalDebtValue >= 110, "CDR must be >= 110.");

        accounts[msg.sender].collateral[token] -= amount;

        require(token.transfer(msg.sender, amount), "Token transfer failed.");

        emit CollateralWithdrawn(msg.sender, token, amount);
    }

    function borrow(IERC20 token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0.");
        require(isSupportedToken(address(token)), "Token not supported.");

        uint256 totalCollateralValue = getTotalCollateralValue(msg.sender);
        uint256 totalDebtValue = getTotalDebtValue(msg.sender) + (amount * mockUniswap.getPriceInUSDC(address(token))) / 1e18;

        require((totalCollateralValue * 100) / totalDebtValue >= 110, "CDR must be >= 110%.");

        accounts[msg.sender].debt[token] += amount;
        tokenToPool[token].borrow(amount, msg.sender);

        emit Borrowed(msg.sender, token, amount);
    }

    function repay(IERC20 token, uint256 amount) external {
        // wrong implementation
        require(amount > 0, "Amount must be greater than 0");
        require(accounts[msg.sender].debt[token] >= amount, "Insufficient debt.");

        uint256 interestFee = (amount * 2) / 100;
        uint256 repaymentAmount = amount - interestFee;

        accounts[msg.sender].debt[token] -= amount;
        token.transferFrom(msg.sender, address(tokenToPool[token]), repaymentAmount);
        token.transferFrom(msg.sender, address(tokenToPool[token]), interestFee);

        tokenToPool[token].distributeEarnings(interestFee);

        emit Repaid(msg.sender, token, amount);
    }

    // liquidate account if CDR < 105%
    // CDR - Collateral to Debt Ratio
    // Collateral = depositedAssets + borrowedAssets
    function liquidate(address trader) external {
        // wrong implementation
        uint256 totalCollateralValue = getTotalCollateralValue(trader); // USDC
        uint256 totalDebtValue = getTotalDebtValue(trader); // USDC

        require((totalCollateralValue * 100) / totalDebtValue <= 105, "CDR must be <= 105%.");

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            IERC20 token = IERC20(supportedTokens[i]);

            uint256 debt = accounts[trader].debt[token];
            uint256 collateral = accounts[trader].collateral[token];

            if (debt > 0 && collateral > 0) {
                uint256 repaymentAmount = (collateral >= debt) ? debt : collateral;

                token.approve(address(tokenToPool[token]), repaymentAmount);

                tokenToPool[token].repay(repaymentAmount);

                accounts[trader].debt[token] -= repaymentAmount;
                accounts[trader].collateral[token] -= repaymentAmount;

                totalDebtValue -= (repaymentAmount * mockUniswap.getPriceInUSDC(address(token))) / 1e18;
                totalCollateralValue -= (repaymentAmount * mockUniswap.getPriceInUSDC(address(token))) / 1e18;
            }
        }

        if (totalDebtValue > 0) {
            for (uint256 i = 0; i < supportedTokens.length; i++) {
                IERC20 debtToken = IERC20(supportedTokens[i]);
                uint256 remainingDebt = accounts[trader].debt[debtToken];

                if (remainingDebt > 0) {
                    for (uint256 j = 0; j < supportedTokens.length; j++) {
                        if (i == j) {
                            continue;
                        }

                        IERC20 collateralToken = IERC20(supportedTokens[j]);
                        uint256 remainingCollateral = accounts[trader].collateral[collateralToken];

                        if (remainingCollateral > 0) {
                            uint256 debtValue = (remainingDebt * mockUniswap.getPriceInUSDC(address(debtToken))) / 1e18;
                            uint256 collateralValue = (remainingCollateral * mockUniswap.getPriceInUSDC(address(collateralToken))) / 1e18;

                            uint256 collateralToUse = (collateralValue >= debtValue) ? debtValue : collateralValue;

                            uint256 amountOut = mockUniswap.swapTokens(address(collateralToken), address(debtToken), remainingCollateral, collateralToUse, block.timestamp + 300);

                            debtToken.approve(address(tokenToPool[debtToken]), amountOut);

                            tokenToPool[debtToken].repay(amountOut);

                            accounts[trader].debt[debtToken] -= (amountOut * remainingDebt) / debtValue;

                            accounts[trader].collateral[collateralToken] -= (collateralToUse * remainingCollateral) / collateralValue;

                            totalDebtValue -= collateralToUse;
                            totalCollateralValue -= collateralToUse;

                            if (totalDebtValue == 0) {
                                break;
                            }
                        }
                    }
                }

                if (totalDebtValue == 0) {
                    break;
                }
            }
        }

        emit Liquidated(trader);
    }

    function isSupportedToken(address token) public view returns (bool) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                return true;
            }
        }

        return false;
    }

    function getTotalCollateralValue(address trader) public view returns (uint256) {
        uint256 totalValue = 0;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            IERC20 token = IERC20(supportedTokens[i]);

            uint256 collateral = accounts[trader].collateral[token];

            if (collateral > 0) {
                totalValue += (collateral * mockUniswap.getPriceInUSDC(address(token))) / 1e18;
            }
        }

        return totalValue;
    }

    function getTotalDebtValue(address trader) public view returns (uint256) {
        uint256 totalValue = 0;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            IERC20 token = IERC20(supportedTokens[i]);

            uint256 debt = accounts[trader].debt[token];

            if (debt > 0) {
                totalValue += (debt * mockUniswap.getPriceInUSDC(address(token))) / 1e18;
            }
        }

        return totalValue;
    }
}
