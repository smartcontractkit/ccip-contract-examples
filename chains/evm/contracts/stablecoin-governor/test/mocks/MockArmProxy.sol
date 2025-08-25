// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

contract MockArmProxy {
  mapping(bytes16 => bool) private _isCursed;

  function setIsCursed(bytes16 subject, bool cursed) external {
    _isCursed[subject] = cursed;
  }

  function isCursed() external view returns (bool) {
    return _isCursed[bytes16(0)];
  }

  function isCursed(
    bytes16 subject
  ) external view returns (bool) {
    return _isCursed[subject];
  }

  function test() external pure {}
}
