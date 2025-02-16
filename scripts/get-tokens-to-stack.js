require('dotenv').config();
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;
const tx = require('@stacks/transactions');
const utils = require('./utils');
const network = utils.resolveNetwork();
const BN = require('bn.js');

async function getTokensToStack() {
  const lastVaultTx = await tx.callReadOnlyFunction({
    contractAddress: CONTRACT_ADDRESS,
    contractName: "arkadiko-stx-reserve-v1-1",
    functionName: "get-tokens-to-stack",
    functionArgs: [tx.stringAsciiCV("stacker-4")],
    senderAddress: CONTRACT_ADDRESS,
    network
  });

  console.log(tx.cvToJSON(lastVaultTx));
  return tx.cvToJSON(lastVaultTx).value;
}

console.log(getTokensToStack());
