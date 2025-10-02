import hre from "hardhat";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log("🚀 Starting ChainCircle deployment...\n");

  const [deployer] = await hre.ethers.getSigners();
  console.log("📍 Deploying contracts with account:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Account balance:", hre.ethers.formatEther(balance), "ETH\n");

  console.log("📝 Deploying Reputation contract...");
  const Reputation = await hre.ethers.getContractFactory("Reputation");
  const reputation = await Reputation.deploy();
  await reputation.waitForDeployment();
  const reputationAddress = await reputation.getAddress();
  console.log("✅ Reputation deployed to:", reputationAddress);

  console.log("\n📝 Deploying ChainCircle contract...");
  const protocolTreasury = deployer.address;
  
  const ChainCircle = await hre.ethers.getContractFactory("ChainCircle");
  const chainCircle = await ChainCircle.deploy(protocolTreasury);
  await chainCircle.waitForDeployment();
  const chainCircleAddress = await chainCircle.getAddress();
  console.log("✅ ChainCircle deployed to:", chainCircleAddress);

  console.log("\n🔗 Authorizing ChainCircle to update reputation...");
  const authTx = await reputation.authorizeCaller(chainCircleAddress);
  await authTx.wait();
  console.log("✅ Authorization complete");

  const deploymentInfo = {
    network: hre.network.name,
    chainId: (await hre.ethers.provider.getNetwork()).chainId.toString(),
    deployer: deployer.address,
    contracts: {
      ChainCircle: chainCircleAddress,
      Reputation: reputationAddress,
    },
    timestamp: new Date().toISOString(),
  };

  const deploymentDir = path.join(__dirname, "../deployments");
  if (!fs.existsSync(deploymentDir)) {
    fs.mkdirSync(deploymentDir, { recursive: true });
  }

  const filename = path.join(
    deploymentDir,
    `${hre.network.name}-${Date.now()}.json`
  );
  fs.writeFileSync(filename, JSON.stringify(deploymentInfo, null, 2));

  console.log("\n📄 Deployment info saved to:", filename);
  console.log("\n🎉 Deployment complete!\n");
  console.log("Contract Addresses:");
  console.log("==================");
  console.log("ChainCircle:", chainCircleAddress);
  console.log("Reputation:", reputationAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });