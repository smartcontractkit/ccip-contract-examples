// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

contract Parameters {
  address TOKEN = 0x0000000000000000000000000000000000000000; // Replace with actual token address
  uint48 INITIAL_DELAY = 3 days; // Replace with actual initial delay
  address GOVERNOR = 0x0000000000000000000000000000000000000000; // Replace with actual governor address
  address CCIP_ROUTER = 0x0000000000000000000000000000000000000000; // Replace with actual CCIP router address
  address RMN_PROXY = 0x0000000000000000000000000000000000000000; // Replace with actual RMN proxy address
  uint8 TOKEN_DECIMALS = 18; // Replace with actual token decimals
  address[] ALLOWLIST; // Replace with actual allowlist addresses
  address OWNER = 0x0000000000000000000000000000000000000000; // If left as address(0), the deployer will be the owner. In the case of token pools deployment, the OWNER needs to call `acceptOwnership` on the token pool contract.
}
