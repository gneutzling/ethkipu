import { network } from "hardhat";

const { ethers } = await network.connect();

async function main() {
  console.log("Deploying KipuBank contract...");

  // Configuration parameters
  const BANK_CAP = ethers.parseEther("100"); // 100 ETH bank cap
  const PRICE_FEED_SEPOLIA = "0x694AA1769357215DE4FAC081bf1f309aDC325306"; // Sepolia ETH/USD price feed

  // For mainnet, you would use: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"
  const PRICE_FEED_MAINNET = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";

  // Determine which price feed to use based on network
  const currentNetwork = await ethers.provider.getNetwork();
  const priceFeed =
    currentNetwork.chainId === 11155111n
      ? PRICE_FEED_SEPOLIA
      : PRICE_FEED_MAINNET;

  console.log(`Network: ${currentNetwork.name} (${currentNetwork.chainId})`);
  console.log(`Using price feed: ${priceFeed}`);
  console.log(`Bank cap: ${ethers.formatEther(BANK_CAP)} ETH`);

  // Deploy the contract
  const kipuBank = await ethers.deployContract("KipuBank", [
    BANK_CAP,
    priceFeed,
  ]);

  const contractAddress = kipuBank.target;
  console.log(`KipuBank deployed to: ${contractAddress}`);

  // Verify deployment
  console.log("\nVerifying deployment...");
  console.log(`Bank cap: ${ethers.formatEther(await kipuBank.BANK_CAP())} ETH`);
  console.log(`Price feed: ${await kipuBank.priceFeed()}`);
  console.log(`ETH alias: ${await kipuBank.ETH_ALIAS()}`);
  console.log(
    `Max withdraw USD: $${ethers.formatUnits(
      await kipuBank.MAX_WITHDRAW_USD(),
      8
    )}`
  );

  // Get current ETH price
  try {
    const priceFeedContract = await ethers.getContractAt(
      "AggregatorV3Interface",
      priceFeed
    );
    const roundData = await priceFeedContract.latestRoundData();
    const ethPrice = ethers.formatUnits(roundData[1], 8);
    console.log(`Current ETH price: $${ethPrice}`);
  } catch (error) {
    console.log("Could not fetch current ETH price from oracle");
  }

  console.log("\nDeployment completed successfully!");
  console.log("\nNext steps:");
  console.log("1. Verify the contract on Etherscan (if on testnet/mainnet)");
  console.log("2. Run tests: npx hardhat test");
  console.log("3. Interact with the contract using the deployed address");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
