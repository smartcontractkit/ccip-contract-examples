// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import "../../script/TokenGovernor.s.sol";

contract TokenGovernorScriptTest is Test {
  address token = makeAddr("token");
  address owner = makeAddr("owner");

  function test_deploy_without_owner() public {
    uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
    if (deployerPrivateKey == 0) {
      return;
    }
    address deployer = vm.addr(deployerPrivateKey);

    DeployScript script = new DeployScript(token, address(0));

    address governor = script.run();

    bytes32 default_admin_role = AccessControl(governor).DEFAULT_ADMIN_ROLE();
    assertTrue(AccessControl(governor).hasRole(default_admin_role, deployer), "test_deploy_without_owner::1");
    assertEq(TokenGovernor(governor).getToken(), token, "test_deploy_without_owner::2");
  }

  function test_deploy_with_owner() public {
    uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
    if (deployerPrivateKey == 0) {
      return;
    }
    address deployer = vm.addr(deployerPrivateKey);

    DeployScript script = new DeployScript(token, owner);

    address governor = script.run();

    bytes32 default_admin_role = AccessControl(governor).DEFAULT_ADMIN_ROLE();
    assertTrue(AccessControl(governor).hasRole(default_admin_role, owner), "test_deploy_with_owner::1");
    assertFalse(AccessControl(governor).hasRole(default_admin_role, deployer), "test_deploy_with_owner::2");
    assertEq(TokenGovernor(governor).getToken(), token, "test_deploy_with_owner::3");
  }
}

contract DeployScript is TokenGovernorScript {
  constructor(address token, address owner) TokenGovernorScript() {
    TOKEN = token;
    OWNER = owner;
  }
}
