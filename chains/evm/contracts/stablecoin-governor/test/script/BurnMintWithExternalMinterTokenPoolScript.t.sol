// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../../script/BurnMintWithExternalMinterTokenPool.s.sol";

contract BurnMintWithExternalMinterTokenPoolScriptTest is Test {
  uint8 tokenDecimals = 18;
  address[] allowlist;
  address rmnProxy = makeAddr("rmnProxy");
  address ccipRouter = makeAddr("ccipRouter");
  address owner = makeAddr("owner");

  function test_deploy_without_owner() public {
    uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
    if (deployerPrivateKey == 0) {
      return;
    }
    address deployer = vm.addr(deployerPrivateKey);

    address token = address(new MockToken(tokenDecimals));
    address minter = address(new MockMinter(token));

    DeployScript script = new DeployScript(minter, tokenDecimals, allowlist, rmnProxy, ccipRouter, address(0));

    address tokenPool = script.run();

    assertEq(BurnMintWithExternalMinterTokenPool(tokenPool).getMinter(), minter, "test_deploy_without_owner::1");
    assertEq(address(BurnMintWithExternalMinterTokenPool(tokenPool).getToken()), token, "test_deploy_without_owner::2");
    assertEq(
      BurnMintWithExternalMinterTokenPool(tokenPool).getTokenDecimals(), tokenDecimals, "test_deploy_without_owner::3"
    );
    assertEq(
      BurnMintWithExternalMinterTokenPool(tokenPool).getAllowList().length,
      allowlist.length,
      "test_deploy_without_owner::4"
    );
    assertEq(BurnMintWithExternalMinterTokenPool(tokenPool).getRmnProxy(), rmnProxy, "test_deploy_without_owner::5");
    assertEq(BurnMintWithExternalMinterTokenPool(tokenPool).getRouter(), ccipRouter, "test_deploy_without_owner::6");
    assertEq(Ownable2Step(tokenPool).owner(), deployer, "test_deploy_without_owner::7");
  }

  function test_deploy_with_owner() public {
    uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
    if (deployerPrivateKey == 0) {
      return;
    }
    address deployer = vm.addr(deployerPrivateKey);

    address token = address(new MockToken(tokenDecimals));
    address minter = address(new MockMinter(token));

    DeployScript script = new DeployScript(minter, tokenDecimals, allowlist, rmnProxy, ccipRouter, owner);

    address tokenPool = script.run();

    assertEq(BurnMintWithExternalMinterTokenPool(tokenPool).getMinter(), minter, "test_deploy_with_owner::1");
    assertEq(address(BurnMintWithExternalMinterTokenPool(tokenPool).getToken()), token, "test_deploy_with_owner::2");
    assertEq(
      BurnMintWithExternalMinterTokenPool(tokenPool).getTokenDecimals(), tokenDecimals, "test_deploy_with_owner::3"
    );
    assertEq(
      BurnMintWithExternalMinterTokenPool(tokenPool).getAllowList().length,
      allowlist.length,
      "test_deploy_with_owner::4"
    );
    assertEq(BurnMintWithExternalMinterTokenPool(tokenPool).getRmnProxy(), rmnProxy, "test_deploy_with_owner::5");
    assertEq(BurnMintWithExternalMinterTokenPool(tokenPool).getRouter(), ccipRouter, "test_deploy_with_owner::6");
    assertEq(Ownable2Step(tokenPool).owner(), deployer, "test_deploy_with_owner::7");

    vm.prank(owner);
    Ownable2Step(tokenPool).acceptOwnership();

    assertEq(Ownable2Step(tokenPool).owner(), owner, "test_deploy_with_owner::8");
  }
}

contract MockToken {
  uint8 public immutable decimals;

  constructor(
    uint8 decimals_
  ) {
    decimals = decimals_;
  }
}

contract MockMinter {
  address public immutable getToken;

  constructor(
    address token_
  ) {
    getToken = token_;
  }
}

contract DeployScript is BurnMintWithExternalMinterTokenPoolScript {
  constructor(
    address minter,
    uint8 tokenDecimals,
    address[] memory allowlist,
    address rmnProxy,
    address ccipRouter,
    address owner
  ) {
    GOVERNOR = minter;
    TOKEN_DECIMALS = tokenDecimals;
    ALLOWLIST = allowlist;
    RMN_PROXY = rmnProxy;
    CCIP_ROUTER = ccipRouter;
    OWNER = owner;
  }
}
