import {
  Account,
  Chain,
  Clarinet,
  Tx,
  types,
} from "https://deno.land/x/clarinet/index.ts";

import { 
  VaultManager,
  VaultLiquidator,
  VaultRewards
} from './models/arkadiko-tests-vaults.ts';

import { 
  OracleManager,
  DikoToken
} from './models/arkadiko-tests-tokens.ts';

import { 
  Stacker
} from './models/arkadiko-tests-stacker.ts';

import * as Utils from './models/arkadiko-tests-utils.ts'; Utils;

Clarinet.test({
  name: "vault-rewards: vault DIKO rewards",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    let deployer = accounts.get("deployer")!;
    let wallet_1 = accounts.get("wallet_1")!;

    let oracleManager = new OracleManager(chain, deployer);
    let vaultManager = new VaultManager(chain, deployer);
    let vaultRewards = new VaultRewards(chain, deployer);

    // Set price, create vault
    oracleManager.updatePrice("STX", 2);
    vaultManager.createVault(deployer, "STX-A", 5, 1);

    // Check rewards
    let call:any = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(320)
    
    chain.mineEmptyBlock(1);

    call = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(640)

    call = vaultRewards.calculateCummulativeRewardPerCollateral();
    call.result.expectUintWithDecimals(128)

    chain.mineEmptyBlock((6*7*144)-5);

    // Need a write action to update the cumm reward 
    vaultManager.createVault(wallet_1, "STX-A", 5, 1);

    call = vaultRewards.calculateCummulativeRewardPerCollateral();
    call.result.expectUintWithDecimals(240298.0593)

    // Almost all rewards - 1.2m
    call = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(1201490.2965)
  },
});

Clarinet.test({
  name: "vault-rewards: emergency shutdown",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    let deployer = accounts.get("deployer")!;
    let wallet_1 = accounts.get("wallet_1")!;

    let oracleManager = new OracleManager(chain, deployer);
    let vaultManager = new VaultManager(chain, deployer);
    let vaultRewards = new VaultRewards(chain, deployer);

    // Set price, create vault
    oracleManager.updatePrice("STX", 2);
    vaultManager.createVault(deployer, "STX-A", 5, 1);

    // Check rewards
    let call:any = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(320)

    // Need to increase cummulative rewards per collateral
    vaultRewards.increaseCummulativeRewardPerCollateral();

    // Only guardian can toggle shutdown
    let result = vaultRewards.toggleEmergencyShutdown(wallet_1);
    result.expectErr().expectUint(20401);

    // Toggle shutdown
    result = vaultRewards.toggleEmergencyShutdown(deployer);
    result.expectOk().expectBool(true);

    // Pending rewards have not changed
    call = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(320)

    // Cumm reward per collateral
    call = vaultRewards.calculateCummulativeRewardPerCollateral();
    call.result.expectUintWithDecimals(64)

    // No changes after 100 blocks
    chain.mineEmptyBlock(100);

    call = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(320)

    call = vaultRewards.calculateCummulativeRewardPerCollateral();
    call.result.expectUintWithDecimals(64)

  },
});

Clarinet.test({
  name: "vault-rewards: claim DIKO rewards",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    let deployer = accounts.get("deployer")!;

    let oracleManager = new OracleManager(chain, deployer);
    let vaultManager = new VaultManager(chain, deployer);
    let vaultRewards = new VaultRewards(chain, deployer);
    let dikoToken = new DikoToken(chain, deployer);

    // Set price, create vault
    oracleManager.updatePrice("STX", 2);
    vaultManager.createVault(deployer, "STX-A", 5, 1);

    chain.mineEmptyBlock(30);

    let call:any = dikoToken.balanceOf(deployer.address);
    call.result.expectOk().expectUintWithDecimals(890000);   

    call = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(9920)

    let result = vaultRewards.claimPendingRewards(deployer);
    result.expectOk().expectUintWithDecimals(9920);

    call = dikoToken.balanceOf(deployer.address);
    call.result.expectOk().expectUintWithDecimals(899920);  

  },
});

Clarinet.test({
  name: "vault-rewards: vault DIKO rewards multiple users",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    let deployer = accounts.get("deployer")!;
    let wallet_1 = accounts.get("wallet_1")!;

    let oracleManager = new OracleManager(chain, deployer);
    let vaultManager = new VaultManager(chain, deployer);
    let vaultRewards = new VaultRewards(chain, deployer);

    // Set price, create vault
    oracleManager.updatePrice("STX", 2);
    vaultManager.createVault(deployer, "STX-A", 5, 1);

    // Check rewards
    let call:any = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(320)

    chain.mineEmptyBlock(5);

    // 6 * 320 = 1920
    call = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(1920)

    vaultManager.createVault(wallet_1, "STX-A", 5, 1);

    // Only half of block rewars (320 / 2) = 160
    call = vaultRewards.getPendingRewards(wallet_1);
    call.result.expectOk().expectUintWithDecimals(160)

    // Already had 1920. 1920 + 160 = 2080
    call = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(2080)

  },
});

Clarinet.test({
  name: "vault-rewards: auto-harvest vault rewards",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    let deployer = accounts.get("deployer")!;

    let oracleManager = new OracleManager(chain, deployer);
    let vaultManager = new VaultManager(chain, deployer);
    let vaultRewards = new VaultRewards(chain, deployer);
    let dikoToken = new DikoToken(chain, deployer);

    // Set price, create vault
    oracleManager.updatePrice("STX", 2);
    vaultManager.createVault(deployer, "STX-A", 50, 1);

    // Check rewards
    let call:any = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(320)

    chain.mineEmptyBlock(5);

    // 6 * 320 = 1920
    call = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(1920)

    call = dikoToken.balanceOf(deployer.address);
    call.result.expectOk().expectUintWithDecimals(890000);   

    // Deposit extra
    vaultManager.deposit(deployer, 1, 500);

    // Deposit will auto harvest
    // So one block later we are at 320 again
    call = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(319.9999)

    // Rewards have been added to wallet
    call = dikoToken.balanceOf(deployer.address);
    call.result.expectOk().expectUintWithDecimals(891920);  

  },
});

Clarinet.test({
  name: "vault-rewards: vault DIKO rewards over time",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    let deployer = accounts.get("deployer")!;
    let wallet_1 = accounts.get("wallet_1")!;

    let oracleManager = new OracleManager(chain, deployer);
    let vaultManager = new VaultManager(chain, deployer);
    let vaultRewards = new VaultRewards(chain, deployer);
    let vaultLiquidator = new VaultLiquidator(chain, deployer);
    let stacker = new Stacker(chain, deployer);

    // Set price, create vault
    oracleManager.updatePrice("STX", 2);
    let result = vaultManager.createVault(deployer, "STX-A", 5000, 1000);
    result.expectOk().expectUintWithDecimals(1000);

    // Check rewards at start
    let call:any = vaultRewards.getPendingRewards(deployer);
    call.result.expectOk().expectUintWithDecimals(320)
    
    // Rewards for 6 weeks = 42 days
    for (let index = 0; index < 50; index++) {

      // Advance 1 day
      chain.mineEmptyBlock(144);

      // Need to increase cumm rewards per collateral
      vaultRewards.increaseCummulativeRewardPerCollateral();

      // Get pending rewards
      let call = vaultRewards.getPendingRewards(deployer);
      
      // Print total rewards - for docs
      // console.log(call.result.expectOk())

      switch (index)
      {
        case 7: call.result.expectOk().expectUintWithDecimals(363054.515); break; // 363k
        case 14: call.result.expectOk().expectUintWithDecimals(650631.305); break; // 650k
        case 21: call.result.expectOk().expectUintWithDecimals(912117.4); break; // 912k
        case 28: call.result.expectOk().expectUintWithDecimals(1150093.67); break; // 1.15 mio
        case 35: call.result.expectOk().expectUintWithDecimals(1366617.03); break; // 1.36 mio
        case 42: call.result.expectOk().expectUintWithDecimals(1510517.6); break; // 1.51 mio
        case 49: call.result.expectOk().expectUintWithDecimals(1510517.6); break; // 1.51 mio
        case 56: call.result.expectOk().expectUintWithDecimals(1510517.6); break; // 1.51 mio
        default: break;
      }
    }
  },
});
