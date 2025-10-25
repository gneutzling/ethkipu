import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("KipuBankModule", (m) => {
  // Get parameters from environment or use defaults
  const bankCap = m.getParameter("bankCap", 100n * 10n ** 18n); // 100 ETH default
  const priceFeed = m.getParameter(
    "priceFeed",
    "0x694AA1769357215DE4FAC081bf1f309aDC325306"
  ); // Sepolia ETH/USD

  const kipuBank = m.contract("KipuBank", [bankCap, priceFeed]);

  return { kipuBank };
});
