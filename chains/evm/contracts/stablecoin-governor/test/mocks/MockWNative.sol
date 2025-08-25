// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockWNative is ERC20 {
  constructor() ERC20("Wrapped Native", "WNative") {}

  function deposit() external payable {
    _mint(msg.sender, msg.value);
  }

  function withdraw(
    uint256 amount
  ) external {
    _burn(msg.sender, amount);
    (bool success,) = msg.sender.call{value: amount}("");
    require(success, "MockWNative::withdraw");
  }

  function test() external pure {}
}
