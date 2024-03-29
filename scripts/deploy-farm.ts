import * as hre from "hardhat";
import { PulseVault } from "../types/ethers-contracts/PulseVault";
import { PulseVault__factory } from "../types/ethers-contracts/factories/PulseVault__factory";
import { Strategy } from "../types/ethers-contracts/Strategy";
import { Strategy__factory } from "../types/ethers-contracts/factories/Strategy__factory";
import address from "../address";

require("dotenv").config();

const { ethers } = hre;

const toEther = (val: any) => {
  return ethers.utils.formatEther(val);
};

const toWei = (val: any, unit = 18) => {
  return ethers.utils.parseUnits(val, unit);
};

async function deploy() {
  console.log(new Date().toLocaleString());

  // const deployer = (await ethers.getSigners()).filter(account => account.address === "0x32f1C25148DeCbdBe69E1cc2F87E0237BC34b700")[0];
  // const deployer = (await ethers.getSigners()).filter(account => account.address === "0x12D16f3A335dfdB575FacE8e3ae6954a1C0e24f1")[0];
  const deployer = (await ethers.getSigners()).filter(account => account.address === "0x647BB910944165D14b961985c28b06b08cA47f77")[0];

  // const deployer = (await ethers.getSigners()).filter(
  //   (account) =>
  //     account.address === "0x7B9e671B6cd10FD782Bdb982D40ffc0435C3C030"
  // )[0];

  console.log("Deploying contracts with the account:", deployer.address);

  const beforeBalance = await deployer.getBalance();
  console.log("Account balance:", (await deployer.getBalance()).toString());

  const mainnet = process.env.NETWORK == "mainnet" ? true : false;
  const url = mainnet ? process.env.URL_MAIN : process.env.URL_TEST;
  const curBlock = await ethers.getDefaultProvider(url).getBlockNumber();
  const vaultAddress = mainnet ? address.mainnet.vault : address.testnet.vault;
  const strategyAddress = mainnet
    ? address.mainnet.strategy
    : address.testnet.strategy;
  const assetAddress = mainnet ? address.mainnet.usdt : address.testnet.usdt;
  const payoutAddress = mainnet
    ? address.mainnet.payoutAgent
    : address.testnet.payoutAgent;

  const strategyFactory: Strategy__factory = new Strategy__factory(deployer);
  let strategy: Strategy = strategyFactory.attach(strategyAddress).connect(deployer);
  // if ("Redeploy" && true) {
  //     strategy = await strategyFactory.deploy(assetAddress);
  // }
  console.log('Strategy: ', strategy.address);

  const vaultFactory: PulseVault__factory = new PulseVault__factory(deployer);
  let vault: PulseVault = vaultFactory.attach(vaultAddress).connect(deployer);
  if ("Redeploy" && true) {
    vault = await vaultFactory.deploy(
      strategy.address,
      assetAddress,
      payoutAddress
    );
  }
  console.log("PulseVault: ", vault.address);

  // await strategy.setVault(vault.address);

  const afterBalance = await deployer.getBalance();
  console.log("Deployed cost:", beforeBalance.sub(afterBalance).toString());
}

deploy()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
