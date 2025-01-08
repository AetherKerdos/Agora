// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MarginAccount.sol";

contract LiquidityPool is AccessControl {

    struct Provider {
        uint256 share;
        uint256 earnings;
    }

    mapping(address => Provider) public providers;
    mapping(address => uint256) public borrowedAmounts;

    address[] public providerAddresses;
    uint256 public totalShares;
    uint256 public totalVolume;
    uint256 public totalEarnings;
    IERC20 public token;
    MarginAccount private marginAccount;

    bytes32 public constant BORROWER_ROLE = keccak256("BORROWER_ROLE");

    // modifier onlyMarginAccount() {
    //     require(msg.sender == marginAccount, "Not authorized.");
    //     _;
    // }

    event LiquidityProvided(address indexed provider, IERC20 token, uint256 amount);
    event LiquidityWithdrawn(address indexed provider, IERC20 token, uint256 amount);
    event EarningsWithdrawn(address indexed provider, IERC20 token, uint256 amount);
    event Borrowed(address indexed borrower, uint256 amount);
    event Repaid(address indexed borrower, uint256 amount);

    constructor(address _token, address _marginAccount) {
        token = IERC20(_token);
        marginAccount = MarginAccount(_marginAccount);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");

        token.transferFrom(msg.sender, address(this), amount);

        if (providers[msg.sender].share == 0) {
            providerAddresses.push(msg.sender);
        }

        providers[msg.sender].share += amount;
        totalShares += amount;
        totalVolume += amount;

        emit LiquidityProvided(msg.sender, token, amount);
    }

    function borrow(uint256 amount, address borrower) external onlyRole(BORROWER_ROLE) {
        require(amount > 0, "Amount must be greater than 0.");
        require(token.balanceOf(address(this)) >= amount, "Insufficient liquidity.");

        token.transfer(borrower, amount);

        borrowedAmounts[borrower] += amount;

        totalVolume -= amount;

        emit Borrowed(borrower, amount);
    }

    function repay(uint256 amount) external onlyRole(BORROWER_ROLE) {
        require(amount > 0, "Amount must be greater than 0.");

        token.transferFrom(msg.sender, address(this), amount);

        borrowedAmounts[msg.sender] -= amount;

        totalVolume += amount;

        emit Repaid(msg.sender, amount);
    }

    function distributeEarnings(uint256 earnings) external onlyRole(BORROWER_ROLE) {
        require(earnings > 0, "Earnings must be greater than 0.");

        totalEarnings += earnings;

        for (uint256 i = 0; i < providerAddresses.length; i ++) {
            address provider = providerAddresses[i];
            uint256 providerEarnings = (earnings * providers[provider].share) / totalShares;
            providers[provider].earnings += providerEarnings;
        }
    }

    function withdrawLiquidity(uint256 amount) external {        
        require(amount > 0, "Amount must be greater than 0.");
        require(providers[msg.sender].earnings >= amount, "Insufficient share.");

        providers[msg.sender].share -= amount;
        totalShares -= amount;
        totalVolume -= amount;

        token.transfer(msg.sender, amount);

        if (providers[msg.sender].share == 0) {
            for (uint256 i = 0; i < providerAddresses.length; i ++) {
                if (providerAddresses[i] == msg.sender) {
                    providerAddresses[i] = providerAddresses[providerAddresses.length - 1];
                    providerAddresses.pop();
                    break;
                }
            }
        }

        emit LiquidityWithdrawn(msg.sender, token, amount);
    }

    function withdrawEarnings(uint256 amount) external {        
        require(amount > 0, "Amount must be greater than 0.");
        require(providers[msg.sender].earnings >= amount, "Insufficient earings.");

        providers[msg.sender].earnings -= amount;
        totalEarnings -= amount;

        token.transfer(msg.sender, amount);

        emit EarningsWithdrawn(msg.sender, token, amount);
    }
}