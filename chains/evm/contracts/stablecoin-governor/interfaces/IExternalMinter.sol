// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExternalMinter {
  function getToken() external view returns (address);
  function mint(address recipient, uint256 amount) external returns (bool);
  function burn(
    uint256 amount
  ) external returns (bool);
}
