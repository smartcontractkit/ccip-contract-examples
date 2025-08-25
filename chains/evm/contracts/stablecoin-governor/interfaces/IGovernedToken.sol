// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGovernedToken is IERC20 {
  event Mint(address indexed caller, address indexed to, uint256 amount);
  event Burn(address indexed caller, address indexed from, uint256 amount);
  event Freeze(address indexed caller, address indexed account);
  event Unfreeze(address indexed caller, address indexed account);

  function mint(
    uint256 amount
  ) external returns (bool);
  function burn(
    uint256 amount
  ) external returns (bool);
  function freeze(
    address account
  ) external;
  function unfreeze(
    address account
  ) external;
  function pause() external;
  function unpause() external;
  function drain(
    address account
  ) external;
  function recoverERC20(address token, address recipient, uint256 amount) external;
  function transferOwnership(
    address newOwner
  ) external;
  function acceptOwnership() external;
}
