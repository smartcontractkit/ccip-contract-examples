// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Minimal interface for the Checker contract
 */
interface IChecker {
  function checkMint(address account, uint256 amount, address minter, bool isBridge) external;
  function checkBurn(address account, uint256 amount, address burner, bool isBridge) external;
}
