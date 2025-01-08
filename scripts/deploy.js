const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

function copyABIs() {
    const contracts = ["LiquidityPool", "MarginAccount", "MockUniswap"];
    const sourceDir = path.join(__dirname, "../artifacts/contracts");
    const abiDestDir = path.join(__dirname, "../frontend/frontend/src/abis");

    // Ensure the destination directory for ABIs exists
    if (!fs.existsSync(abiDestDir)) {
        fs.mkdirSync(abiDestDir, { recursive: true });
    }

    // Copy each contract's ABI
    contracts.forEach((contract) => {
        const sourcePath = path.join(sourceDir, `${contract}.sol`, `${contract}.json`);
        const destPath = path.join(abiDestDir, `${contract}.json`);

        if (fs.existsSync(sourcePath)) {
            fs.copyFileSync(sourcePath, destPath);
            console.log(`Copied ${contract}.json to frontend/frontend/src/abis/`);
        } else {
            console.error(`Artifact for ${contract} not found at ${sourcePath}`);
        }
    });

    // Copy deployed-addresses.json to frontend/frontend/src/deployed-addresses.js
    const addressesSourcePath = path.join(__dirname, "../deployed-addresses.json");
    const addressesDestPath = path.join(__dirname, "../frontend/frontend/src/deployed-addresses.js");

    if (fs.existsSync(addressesSourcePath)) {
        // Read the JSON file
        const addresses = JSON.parse(fs.readFileSync(addressesSourcePath, "utf8"));

        // Convert the JSON object to a JavaScript export statement
        const jsContent = `export const deployedAddresses = ${JSON.stringify(addresses, null, 2)};`;

        // Write the JS file
        fs.writeFileSync(addressesDestPath, jsContent);
        console.log(`Copied deployed-addresses.json to frontend/frontend/src/deployed-addresses.js`);
    } else {
        console.error(`deployed-addresses.json not found at ${addressesSourcePath}`);
    }
}

async function main() {
    // Get the contract factories
    const LiquidityPool = await ethers.getContractFactory("LiquidityPool");
    const MarginAccount = await ethers.getContractFactory("MarginAccount");
    const MockUniswap = await ethers.getContractFactory("MockUniswap");

    // Deploy MockUniswap
    console.log("Deploying MockUniswap...");
    const mockUniswap = await MockUniswap.deploy();
    await mockUniswap.waitForDeployment();
    console.log("MockUniswap deployed to:", await mockUniswap.getAddress());

    // Define token addresses for each liquidity pool
    const tokens = [
        "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // USDC
        "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH
        "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", // WBTC
    ];

    // Deploy 3 LiquidityPool contracts, each with a different token
    const liquidityPools = [];
    for (let i = 0; i < tokens.length; i++) {
        console.log(`Deploying LiquidityPool ${i + 1}...`);
        const liquidityPool = await LiquidityPool.deploy(
            tokens[i], // Token address
            await mockUniswap.getAddress() // MockUniswap address
        );
        await liquidityPool.waitForDeployment();
        console.log(`LiquidityPool ${i + 1} deployed to:`, await liquidityPool.getAddress());
        liquidityPools.push(liquidityPool);
    }

    // Extract the addresses of the deployed liquidity pools
    const liquidityPoolAddresses = await Promise.all(
        liquidityPools.map(async (pool) => await pool.getAddress())
    );

    // Deploy MarginAccount
    console.log("Deploying MarginAccount...");
    const marginAccount = await MarginAccount.deploy(
        tokens, // Array of supported tokens
        liquidityPoolAddresses, // Array of corresponding pool addresses
        await mockUniswap.getAddress() // MockUniswap address
    );
    await marginAccount.waitForDeployment();
    console.log("MarginAccount deployed to:", await marginAccount.getAddress());

    // Save the contract addresses to a file
    const addresses = {
        MockUniswap: await mockUniswap.getAddress(),
        LiquidityPools: liquidityPoolAddresses,
        MarginAccount: await marginAccount.getAddress(),
    };
    require("fs").writeFileSync("deployed-addresses.json", JSON.stringify(addresses, null, 2));
    console.log("Contract addresses saved to deployed-addresses.json");

    // Copy ABIs to the frontend
    copyABIs();
}

// Run the deployment script
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });