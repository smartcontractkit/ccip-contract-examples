// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../../script/CheckerCounter.s.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CheckerCounterScriptTest is Test {
  address governor = makeAddr("governor");
  address owner = makeAddr("owner");

  function test_deploy_without_owner() public {
    uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
    if (deployerPrivateKey == 0) {
      return;
    }
    address deployer = vm.addr(deployerPrivateKey);

    DeployScript script = new DeployScript(governor, address(0));

    (address proxyChecker, address proxyAdmin, address checkerImplementation) = script.run();

    assertEq(CheckerCounter(proxyChecker).getGovernor(), governor, "test_deploy_without_owner::1");
    assertEq(
      checkerImplementation,
      address(uint160(uint256(vm.load(proxyChecker, ERC1967Utils.IMPLEMENTATION_SLOT)))),
      "test_deploy_without_owner::2"
    );
    assertEq(
      proxyAdmin,
      address(uint160(uint256(vm.load(proxyChecker, ERC1967Utils.ADMIN_SLOT)))),
      "test_deploy_without_owner::3"
    );
    assertEq(Ownable(proxyAdmin).owner(), deployer, "test_deploy_without_owner::4");
  }

  function test_deploy_with_owner() public {
    uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
    if (deployerPrivateKey == 0) {
      return;
    }

    DeployScript script = new DeployScript(governor, owner);

    (address proxyChecker, address proxyAdmin, address checkerImplementation) = script.run();

    assertEq(CheckerCounter(proxyChecker).getGovernor(), governor, "test_deploy_with_owner::1");
    assertEq(
      checkerImplementation,
      address(uint160(uint256(vm.load(proxyChecker, ERC1967Utils.IMPLEMENTATION_SLOT)))),
      "test_deploy_with_owner::2"
    );
    assertEq(
      proxyAdmin, address(uint160(uint256(vm.load(proxyChecker, ERC1967Utils.ADMIN_SLOT)))), "test_deploy_with_owner::3"
    );
    assertEq(Ownable(proxyAdmin).owner(), owner, "test_deploy_with_owner::4");
  }
}

contract DeployScript is CheckerCounterScript {
  constructor(address governor, address owner) CheckerCounterScript() {
    GOVERNOR = governor;
    OWNER = owner;
  }
}
