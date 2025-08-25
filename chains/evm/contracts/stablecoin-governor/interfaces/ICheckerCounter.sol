// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IChecker} from "./IChecker.sol";

interface ICheckerCounter is IChecker {
  error OnlyGovernor();
  error ZeroAddressNotAllowed();
  error InvalidRange(uint256 start, uint256 end);

  event Minted(address indexed minter, uint256 amount, uint256 totalMinterMinted, uint256 totalGlobalMinted);
  event Burned(address indexed burner, uint256 amount, uint256 totalBurnerBurned, uint256 totalGlobalBurned);

  function getGovernor() external view returns (address);
  function getMintersCount() external view returns (uint256);
  function getBurnersCount() external view returns (uint256);
  function getMinters(uint256 start, uint256 end) external view returns (address[] memory);
  function getBurners(uint256 start, uint256 end) external view returns (address[] memory);
  function getTotalMinted() external view returns (uint256);
  function getTotalBurned() external view returns (uint256);
  function getTotalBurnedBy(
    address burner
  ) external view returns (uint256);
  function getTotalMintedBy(
    address minter
  ) external view returns (uint256);
}
