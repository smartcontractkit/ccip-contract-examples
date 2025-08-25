// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../checkers/CheckerCounter.sol";
import "./Parameters.sol";

contract CheckerCounterScript is Script, Parameters {
  function run() external returns (address proxyChecker, address proxyAdmin, address checkerImplementation) {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    vm.startBroadcast(deployerPrivateKey);

    address owner = OWNER == address(0) ? deployer : OWNER;

    checkerImplementation = address(new CheckerCounter(GOVERNOR));
    proxyChecker = address(new TransparentUpgradeableProxy(checkerImplementation, owner, ""));

    proxyAdmin = address(uint160(uint256(vm.load(proxyChecker, ERC1967Utils.ADMIN_SLOT))));

    vm.stopBroadcast();
  }
}
