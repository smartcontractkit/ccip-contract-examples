// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/access/IAccessControl.sol";

import "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "../TokenGovernor.sol";
import "./utils/Stablecoin.sol";

contract TokenGovernorTest is Test {
  TokenGovernor governor;
  Stablecoin stablecoin;

  address admin = makeAddr("admin");
  address alice = makeAddr("alice");
  address bob = makeAddr("bob");
  address charlie = makeAddr("charlie");
  address bridge = makeAddr("bridge");

  event CheckerUpdated(address indexed previousChecker, address indexed newChecker);
  event NativeMint(address indexed caller, address indexed recipient, uint256 amount);
  event BridgeMint(address indexed caller, address indexed recipient, uint256 amount);
  event NativeBurn(address indexed caller, address indexed from, uint256 amount);
  event BridgeBurn(address indexed caller, address indexed from, uint256 amount);
  event AccountFrozen(address indexed caller, address indexed account);
  event AccountUnfrozen(address indexed caller, address indexed account);
  event ContractPaused(address indexed caller);
  event ContractUnpaused(address indexed caller);
  event OwnershipTransferred(address indexed caller, address indexed newOwner);
  event OwnershipAccepted(address indexed caller);
  event TokensRecovered(
    address indexed caller, address indexed tokenAddress, address indexed recipient, uint256 amount
  );
  event GovernedTokensRecovered(
    address indexed caller, address indexed token, address indexed recipient, uint256 amount
  );
  event FrozenAccountDrained(address indexed caller, address indexed account);
  event TokenFunctionExecuted(address indexed caller, bytes data, bytes returnData);

  function setUp() public {
    vm.startPrank(admin);

    stablecoin = new Stablecoin();
    stablecoin.initialize("Stablecoin", "STABLE");

    governor = new TokenGovernor(address(stablecoin), 0, admin);

    stablecoin.transferOwnership(address(governor));
    governor.acceptOwnership();

    vm.stopPrank();
  }

  function test_Constructor() public {
    assertEq(governor.getToken(), address(stablecoin), "test_Constructor::1");
    assertEq(governor.getChecker(), address(0), "test_Constructor::2");
    assertEq(governor.hasRole(governor.DEFAULT_ADMIN_ROLE(), admin), true, "test_Constructor::3");
    assertEq(governor.owner(), admin, "test_Constructor::4");
    assertEq(governor.defaultAdmin(), admin, "test_Constructor::5");

    (address newAdmin, uint48 schedule) = governor.pendingDefaultAdmin();
    assertEq(newAdmin, address(0), "test_Constructor::6");
    assertEq(schedule, 0, "test_Constructor::7");
    assertEq(governor.defaultAdminDelay(), 0, "test_Constructor::8");

    uint48 newDelay;
    (newDelay, schedule) = governor.pendingDefaultAdminDelay();
    assertEq(newDelay, 0, "test_Constructor::9");
    assertEq(schedule, 0, "test_Constructor::10");

    assertEq(governor.defaultAdminDelayIncreaseWait(), 5 days, "test_Constructor::11");

    vm.expectRevert(ITokenGovernor.ZeroAddressNotAllowed.selector);
    new TokenGovernor(address(0), 0, admin);
  }

  function test_SupportInterface() public view {
    assertTrue(governor.supportsInterface(type(IAccessControlEnumerable).interfaceId), "test_SupportInterface::1");
    assertTrue(
      governor.supportsInterface(type(IAccessControlDefaultAdminRules).interfaceId), "test_SupportInterface::2"
    );
    assertTrue(governor.supportsInterface(type(IAccessControl).interfaceId), "test_SupportInterface::2");
    assertTrue(governor.supportsInterface(type(IERC165).interfaceId), "test_SupportInterface::2");
  }

  function test_GetAdmins() public {
    address[] memory admins = governor.getAdmins();

    assertEq(admins.length, 1, "test_GetAdmins::1");
    assertEq(admins[0], admin, "test_GetAdmins::2");

    bytes32 role = governor.DEFAULT_ADMIN_ROLE();

    vm.expectRevert(IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminRules.selector);
    governor.grantRole(role, alice);
  }

  function testFuzz_GetMinters(
    address[] memory minters
  ) public {
    vm.startPrank(admin);

    uint256 length = minters.length > 16 ? 16 : minters.length;
    assembly {
      mstore(minters, length)
    }

    uint256 last = 0;
    for (uint256 i = 0; i < length; i++) {
      minters[i] = _boundAddress(minters[i], last + 1, type(uint160).max - length + (i + 1));

      governor.grantRole(governor.MINTER_ROLE(), minters[i]);
      last = uint256(uint160(minters[i]));
    }

    address[] memory result = governor.getMinters();
    assertEq(result.length, minters.length, "testFuzz_GetMinters::1");
    assertEq(governor.getRoleMemberCount(governor.MINTER_ROLE()), minters.length, "testFuzz_GetMinters::1");

    address[] memory result2 = governor.getRoleMembers(governor.MINTER_ROLE());

    for (uint256 i = 0; i < length; i++) {
      assertTrue(governor.hasRole(governor.MINTER_ROLE(), minters[i]), "testFuzz_GetMinters::2");
      assertEq(result2[i], minters[i], "testFuzz_GetMinters::2");
      assertEq(governor.getRoleMember(governor.MINTER_ROLE(), i), minters[i], "testFuzz_GetMinters::2");
      assertEq(result[i], minters[i], "testFuzz_GetMinters::3");
    }

    for (uint256 i = 0; i < minters.length; i++) {
      governor.revokeRole(governor.MINTER_ROLE(), minters[i]);

      assertFalse(governor.hasRole(governor.MINTER_ROLE(), minters[i]), "testFuzz_GetMinters::4");
    }

    vm.stopPrank();
  }

  function testFuzz_GetBridgeMintersOrBurners(
    address[] memory minters
  ) public {
    vm.startPrank(admin);

    uint256 length = minters.length > 16 ? 16 : minters.length;
    assembly {
      mstore(minters, length)
    }

    uint256 last = 0;
    for (uint256 i = 0; i < length; i++) {
      minters[i] = _boundAddress(minters[i], last + 1, type(uint160).max - length + (i + 1));

      governor.grantRole(governor.BRIDGE_MINTER_OR_BURNER_ROLE(), minters[i]);
      last = uint256(uint160(minters[i]));
    }

    address[] memory result = governor.getBridgeMintersOrBurners();
    assertEq(result.length, minters.length, "testFuzz_GetBridgeMintersOrBurners::1");

    for (uint256 i = 0; i < length; i++) {
      assertTrue(
        governor.hasRole(governor.BRIDGE_MINTER_OR_BURNER_ROLE(), minters[i]), "testFuzz_GetBridgeMintersOrBurners::2"
      );
      assertEq(result[i], minters[i], "testFuzz_GetBridgeMintersOrBurners::3");
    }

    for (uint256 i = 0; i < minters.length; i++) {
      governor.revokeRole(governor.BRIDGE_MINTER_OR_BURNER_ROLE(), minters[i]);

      assertFalse(
        governor.hasRole(governor.BRIDGE_MINTER_OR_BURNER_ROLE(), minters[i]), "testFuzz_GetBridgeMintersOrBurners::4"
      );
    }

    vm.stopPrank();
  }

  function testFuzz_GetBurners(
    address[] memory burners
  ) public {
    vm.startPrank(admin);

    uint256 length = burners.length > 16 ? 16 : burners.length;
    assembly {
      mstore(burners, length)
    }

    uint256 last = 0;
    for (uint256 i = 0; i < length; i++) {
      burners[i] = _boundAddress(burners[i], last + 1, type(uint160).max - length + (i + 1));

      governor.grantRole(governor.BURNER_ROLE(), burners[i]);
      last = uint256(uint160(burners[i]));
    }

    address[] memory result = governor.getBurners();
    assertEq(result.length, burners.length, "testFuzz_GetBurners::1");

    for (uint256 i = 0; i < length; i++) {
      assertTrue(governor.hasRole(governor.BURNER_ROLE(), burners[i]), "testFuzz_GetBurners::2");
      assertEq(result[i], burners[i], "testFuzz_GetBurners::3");
    }

    for (uint256 i = 0; i < burners.length; i++) {
      governor.revokeRole(governor.BURNER_ROLE(), burners[i]);

      assertFalse(governor.hasRole(governor.BURNER_ROLE(), burners[i]), "testFuzz_GetBurners::4");
    }

    vm.stopPrank();
  }

  function testFuzz_GetFreezers(
    address[] memory freezers
  ) public {
    vm.startPrank(admin);

    uint256 length = freezers.length > 16 ? 16 : freezers.length;
    assembly {
      mstore(freezers, length)
    }

    uint256 last = 0;
    for (uint256 i = 0; i < length; i++) {
      freezers[i] = _boundAddress(freezers[i], last + 1, type(uint160).max - length + (i + 1));

      governor.grantRole(governor.FREEZER_ROLE(), freezers[i]);
      last = uint256(uint160(freezers[i]));
    }

    address[] memory result = governor.getFreezers();
    assertEq(result.length, freezers.length, "testFuzz_GetFreezers::1");

    for (uint256 i = 0; i < length; i++) {
      assertTrue(governor.hasRole(governor.FREEZER_ROLE(), freezers[i]), "testFuzz_GetFreezers::2");
      assertEq(result[i], freezers[i], "testFuzz_GetFreezers::3");
    }

    for (uint256 i = 0; i < freezers.length; i++) {
      governor.revokeRole(governor.FREEZER_ROLE(), freezers[i]);

      assertFalse(governor.hasRole(governor.FREEZER_ROLE(), freezers[i]), "testFuzz_GetFreezers::4");
    }

    vm.stopPrank();
  }

  function testFuzz_GetUnfreezers(
    address[] memory unfreezers
  ) public {
    vm.startPrank(admin);

    uint256 length = unfreezers.length > 16 ? 16 : unfreezers.length;
    assembly {
      mstore(unfreezers, length)
    }

    uint256 last = 0;
    for (uint256 i = 0; i < length; i++) {
      unfreezers[i] = _boundAddress(unfreezers[i], last + 1, type(uint160).max - length + (i + 1));

      governor.grantRole(governor.UNFREEZER_ROLE(), unfreezers[i]);
      last = uint256(uint160(unfreezers[i]));
    }

    address[] memory result = governor.getUnfreezers();
    assertEq(result.length, unfreezers.length, "testFuzz_GetUnfreezers::1");

    for (uint256 i = 0; i < length; i++) {
      assertTrue(governor.hasRole(governor.UNFREEZER_ROLE(), unfreezers[i]), "testFuzz_GetUnfreezers::2");
      assertEq(result[i], unfreezers[i], "testFuzz_GetUnfreezers::3");
    }

    for (uint256 i = 0; i < unfreezers.length; i++) {
      governor.revokeRole(governor.UNFREEZER_ROLE(), unfreezers[i]);

      assertFalse(governor.hasRole(governor.UNFREEZER_ROLE(), unfreezers[i]), "testFuzz_GetUnfreezers::4");
    }

    vm.stopPrank();
  }

  function testFuzz_GetPausers(
    address[] memory pausers
  ) public {
    vm.startPrank(admin);

    uint256 length = pausers.length > 16 ? 16 : pausers.length;
    assembly {
      mstore(pausers, length)
    }

    uint256 last = 0;
    for (uint256 i = 0; i < length; i++) {
      pausers[i] = _boundAddress(pausers[i], last + 1, type(uint160).max - length + (i + 1));

      governor.grantRole(governor.PAUSER_ROLE(), pausers[i]);
      last = uint256(uint160(pausers[i]));
    }

    address[] memory result = governor.getPausers();
    assertEq(result.length, pausers.length, "testFuzz_GetPausers::1");

    for (uint256 i = 0; i < length; i++) {
      assertTrue(governor.hasRole(governor.PAUSER_ROLE(), pausers[i]), "testFuzz_GetPausers::2");
      assertEq(result[i], pausers[i], "testFuzz_GetPausers::3");
    }

    for (uint256 i = 0; i < pausers.length; i++) {
      governor.revokeRole(governor.PAUSER_ROLE(), pausers[i]);

      assertFalse(governor.hasRole(governor.PAUSER_ROLE(), pausers[i]), "testFuzz_GetPausers::4");
    }

    vm.stopPrank();
  }

  function testFuzz_GetUnpausers(
    address[] memory unpausers
  ) public {
    vm.startPrank(admin);

    uint256 length = unpausers.length > 16 ? 16 : unpausers.length;
    assembly {
      mstore(unpausers, length)
    }

    uint256 last = 0;
    for (uint256 i = 0; i < length; i++) {
      unpausers[i] = _boundAddress(unpausers[i], last + 1, type(uint160).max - length + (i + 1));

      governor.grantRole(governor.UNPAUSER_ROLE(), unpausers[i]);
      last = uint256(uint160(unpausers[i]));
    }

    address[] memory result = governor.getUnpausers();
    assertEq(result.length, unpausers.length, "testFuzz_GetUnpausers::1");

    for (uint256 i = 0; i < length; i++) {
      assertTrue(governor.hasRole(governor.UNPAUSER_ROLE(), unpausers[i]), "testFuzz_GetUnpausers::2");
      assertEq(result[i], unpausers[i], "testFuzz_GetUnpausers::3");
    }

    for (uint256 i = 0; i < unpausers.length; i++) {
      governor.revokeRole(governor.UNPAUSER_ROLE(), unpausers[i]);

      assertFalse(governor.hasRole(governor.UNPAUSER_ROLE(), unpausers[i]), "testFuzz_GetUnpausers::4");
    }

    vm.stopPrank();
  }

  function testFuzz_GetRecoveryManagers(
    address[] memory recoveryManagers
  ) public {
    vm.startPrank(admin);

    uint256 length = recoveryManagers.length > 16 ? 16 : recoveryManagers.length;
    assembly {
      mstore(recoveryManagers, length)
    }

    uint256 last = 0;
    for (uint256 i = 0; i < length; i++) {
      recoveryManagers[i] = _boundAddress(recoveryManagers[i], last + 1, type(uint160).max - length + (i + 1));

      governor.grantRole(governor.RECOVERY_ROLE(), recoveryManagers[i]);
      last = uint256(uint160(recoveryManagers[i]));
    }

    address[] memory result = governor.getRecoveryManagers();
    assertEq(result.length, recoveryManagers.length, "testFuzz_GetRecoveryManagers::1");

    for (uint256 i = 0; i < length; i++) {
      assertTrue(governor.hasRole(governor.RECOVERY_ROLE(), recoveryManagers[i]), "testFuzz_GetRecoveryManagers::2");
      assertEq(result[i], recoveryManagers[i], "testFuzz_GetRecoveryManagers::3");
    }

    for (uint256 i = 0; i < recoveryManagers.length; i++) {
      governor.revokeRole(governor.RECOVERY_ROLE(), recoveryManagers[i]);

      assertFalse(governor.hasRole(governor.RECOVERY_ROLE(), recoveryManagers[i]), "testFuzz_GetRecoveryManagers::4");
    }

    vm.stopPrank();
  }

  function testFuzz_GetCheckerAdmins(
    address[] memory checkerAdmins
  ) public {
    vm.startPrank(admin);

    uint256 length = checkerAdmins.length > 16 ? 16 : checkerAdmins.length;
    assembly {
      mstore(checkerAdmins, length)
    }

    uint256 last = 0;
    for (uint256 i = 0; i < length; i++) {
      checkerAdmins[i] = _boundAddress(checkerAdmins[i], last + 1, type(uint160).max - length + (i + 1));

      governor.grantRole(governor.CHECKER_ADMIN_ROLE(), checkerAdmins[i]);
      last = uint256(uint160(checkerAdmins[i]));
    }

    address[] memory result = governor.getCheckerAdmins();
    assertEq(result.length, checkerAdmins.length, "testFuzz_GetCheckerAdmins::1");

    for (uint256 i = 0; i < length; i++) {
      assertTrue(governor.hasRole(governor.CHECKER_ADMIN_ROLE(), checkerAdmins[i]), "testFuzz_GetCheckerAdmins::2");
      assertEq(result[i], checkerAdmins[i], "testFuzz_GetCheckerAdmins::3");
    }

    for (uint256 i = 0; i < checkerAdmins.length; i++) {
      governor.revokeRole(governor.CHECKER_ADMIN_ROLE(), checkerAdmins[i]);

      assertFalse(governor.hasRole(governor.CHECKER_ADMIN_ROLE(), checkerAdmins[i]), "testFuzz_GetCheckerAdmins::4");
    }

    vm.stopPrank();
  }

  function testFuzz_GetTokenBalance(
    uint256 amount
  ) public {
    assertEq(governor.getTokenBalance(), 0, "testFuzz_GetTokenBalance::1");

    vm.prank(address(governor));
    stablecoin.mint(amount);

    assertEq(governor.getTokenBalance(), amount, "testFuzz_GetTokenBalance::2");
  }

  function testFuzz_SetChecker(
    address newChecker
  ) public {
    vm.startPrank(admin);
    governor.grantRole(governor.CHECKER_ADMIN_ROLE(), admin);

    assertEq(governor.getChecker(), address(0), "testFuzz_SetChecker::1");

    vm.expectEmit(true, true, true, true);
    emit CheckerUpdated(address(0), newChecker);
    governor.setChecker(newChecker);

    assertEq(governor.getChecker(), newChecker, "testFuzz_SetChecker::2");

    vm.expectEmit(true, true, true, true);
    emit CheckerUpdated(newChecker, address(0));
    governor.setChecker(address(0));

    assertEq(governor.getChecker(), address(0), "testFuzz_SetChecker::3");

    governor.revokeRole(governor.CHECKER_ADMIN_ROLE(), admin);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, admin, governor.CHECKER_ADMIN_ROLE()
      )
    );
    governor.setChecker(newChecker);

    vm.stopPrank();
  }

  function testFuzz_Mint(uint256 amount0, uint256 amount1) public {
    amount0 = bound(amount0, 1, type(uint256).max - 1);
    amount1 = bound(amount1, 1, type(uint256).max - amount0);

    vm.startPrank(admin);
    governor.grantRole(governor.MINTER_ROLE(), alice);
    governor.grantRole(governor.BRIDGE_MINTER_OR_BURNER_ROLE(), bridge);
    vm.stopPrank();

    assertEq(stablecoin.balanceOf(admin), 0, "testFuzz_Mint::1");

    vm.expectEmit(true, true, true, true);
    emit NativeMint(alice, alice, amount0);
    vm.prank(alice);
    governor.mint(amount0);

    assertEq(stablecoin.balanceOf(alice), amount0, "testFuzz_Mint::2");
    assertEq(stablecoin.totalSupply(), amount0, "testFuzz_Mint::3");

    vm.expectEmit(true, true, true, true);
    emit BridgeMint(bridge, bridge, amount1);
    vm.prank(bridge);
    governor.mint(amount1);

    assertEq(stablecoin.balanceOf(bridge), amount1, "testFuzz_Mint::4");
    assertEq(stablecoin.totalSupply(), amount0 + amount1, "testFuzz_Mint::5");

    vm.prank(admin);
    vm.expectRevert(ITokenGovernor.OnlyMinterOrBridge.selector);
    governor.mint(1);
  }

  function testFuzz_Mint(address to0, address to1, uint256 amount0, uint256 amount1) public {
    to0 = _boundAddress(to0, 1, type(uint160).max - 1);
    to1 = _boundAddress(to1, uint160(to0) + 1, type(uint160).max);

    vm.assume(to0 != address(governor) && to1 != address(governor));

    amount0 = bound(amount0, 1, type(uint256).max - 1);
    amount1 = bound(amount1, 1, type(uint256).max - amount0);

    vm.startPrank(admin);
    governor.grantRole(governor.MINTER_ROLE(), alice);
    governor.grantRole(governor.BRIDGE_MINTER_OR_BURNER_ROLE(), bridge);
    vm.stopPrank();

    assertEq(stablecoin.balanceOf(to0), 0, "testFuzz_Mint::1");
    assertEq(stablecoin.balanceOf(to1), 0, "testFuzz_Mint::2");

    vm.expectEmit(true, true, true, true);
    emit NativeMint(alice, to0, amount0);
    vm.prank(alice);
    governor.mint(to0, amount0);

    assertEq(stablecoin.balanceOf(to0), amount0, "testFuzz_Mint::3");
    assertEq(stablecoin.totalSupply(), amount0, "testFuzz_Mint::4");

    vm.expectEmit(true, true, true, true);
    emit BridgeMint(bridge, to1, amount1);
    vm.prank(bridge);
    governor.mint(to1, amount1);

    assertEq(stablecoin.balanceOf(to1), amount1, "testFuzz_Mint::5");
    assertEq(stablecoin.totalSupply(), amount0 + amount1, "testFuzz_Mint::6");

    vm.prank(admin);
    vm.expectRevert(ITokenGovernor.OnlyMinterOrBridge.selector);
    governor.mint(to0, 1);

    vm.prank(bridge);
    vm.expectRevert(ITokenGovernor.InvalidRecipient.selector);
    governor.mint(address(governor), 1);
  }

  function testFuzz_Burn(uint256 amount0, uint256 amount1) public {
    amount0 = bound(amount0, 1, type(uint256).max - 1);
    amount1 = bound(amount1, 1, type(uint256).max - amount0);

    vm.startPrank(admin);
    governor.grantRole(governor.BURNER_ROLE(), alice);
    governor.grantRole(governor.BRIDGE_MINTER_OR_BURNER_ROLE(), bridge);
    vm.stopPrank();

    vm.startPrank(bridge);
    governor.mint(alice, amount0);
    governor.mint(bridge, amount1);
    vm.stopPrank();

    assertEq(stablecoin.totalSupply(), amount0 + amount1, "testFuzz_Burn::1");

    vm.startPrank(alice);
    stablecoin.approve(address(governor), amount0);
    vm.expectEmit(true, true, true, true);
    emit NativeBurn(alice, alice, amount0);
    governor.burn(amount0);
    vm.stopPrank();

    assertEq(stablecoin.balanceOf(alice), 0, "testFuzz_Burn::2");
    assertEq(stablecoin.balanceOf(address(governor)), 0, "testFuzz_Burn::3");
    assertEq(stablecoin.totalSupply(), amount1, "testFuzz_Burn::4");

    vm.startPrank(bridge);
    stablecoin.approve(address(governor), amount1);
    vm.expectEmit(true, true, true, true);
    emit BridgeBurn(bridge, bridge, amount1);
    governor.burn(amount1);
    vm.stopPrank();

    assertEq(stablecoin.balanceOf(bridge), 0, "testFuzz_Burn::5");
    assertEq(stablecoin.balanceOf(address(governor)), 0, "testFuzz_Burn::6");
    assertEq(stablecoin.totalSupply(), 0, "testFuzz_Burn::7");

    vm.prank(admin);
    vm.expectRevert(ITokenGovernor.OnlyBurnerOrBridge.selector);
    governor.burn(1);
  }

  function testFuzz_BurnFrom(address from0, address from1, uint256 amount0, uint256 amount1) public {
    from0 = _boundAddress(from0, 1, type(uint160).max - 1);
    from1 = _boundAddress(from1, uint160(from0) + 1, type(uint160).max);

    vm.assume(from0 != address(governor) && from1 != address(governor));

    amount0 = bound(amount0, 1, type(uint256).max - 1);
    amount1 = bound(amount1, 1, type(uint256).max - amount0);

    vm.startPrank(admin);
    governor.grantRole(governor.BURNER_ROLE(), alice);
    governor.grantRole(governor.BRIDGE_MINTER_OR_BURNER_ROLE(), bridge);
    vm.stopPrank();

    vm.startPrank(bridge);
    governor.mint(from0, amount0);
    governor.mint(from1, amount1);
    vm.stopPrank();

    assertEq(stablecoin.totalSupply(), amount0 + amount1, "testFuzz_BurnFrom::1");

    vm.prank(from0);
    stablecoin.approve(address(governor), amount0);

    vm.expectEmit(true, true, true, true);
    emit NativeBurn(alice, from0, amount0);
    vm.prank(alice);
    governor.burnFrom(from0, amount0);

    assertEq(stablecoin.balanceOf(from0), 0, "testFuzz_BurnFrom::2");
    assertEq(stablecoin.balanceOf(address(governor)), 0, "testFuzz_BurnFrom::3");
    assertEq(stablecoin.totalSupply(), amount1, "testFuzz_BurnFrom::4");

    vm.prank(from1);
    stablecoin.approve(address(governor), amount1);

    vm.expectEmit(true, true, true, true);
    emit BridgeBurn(bridge, from1, amount1);
    vm.prank(bridge);
    governor.burnFrom(from1, amount1);

    assertEq(stablecoin.balanceOf(from1), 0, "testFuzz_BurnFrom::5");
    assertEq(stablecoin.balanceOf(address(governor)), 0, "testFuzz_BurnFrom::6");
    assertEq(stablecoin.totalSupply(), 0, "testFuzz_BurnFrom::7");

    vm.prank(admin);
    vm.expectRevert(ITokenGovernor.OnlyBurnerOrBridge.selector);
    governor.burnFrom(from0, 1);

    vm.prank(bridge);
    vm.expectRevert(ITokenGovernor.InvalidFrom.selector);
    governor.burnFrom(address(governor), 1);
  }

  function testFuzz_Freeze(address account0, address account1) public {
    account0 = _boundAddress(account0, 1, type(uint160).max - 1);
    account1 = _boundAddress(account1, uint160(account0) + 1, type(uint160).max);

    vm.startPrank(admin);
    governor.grantRole(governor.FREEZER_ROLE(), alice);
    vm.stopPrank();

    assertFalse(stablecoin.frozen(account0), "testFuzz_Freeze::1");
    assertFalse(stablecoin.frozen(account1), "testFuzz_Freeze::2");

    vm.expectEmit(true, true, true, true);
    emit AccountFrozen(alice, account0);
    vm.prank(alice);
    governor.freeze(account0);

    assertTrue(stablecoin.frozen(account0), "testFuzz_Freeze::3");
    assertFalse(stablecoin.frozen(account1), "testFuzz_Freeze::4");

    vm.expectEmit(true, true, true, true);
    emit AccountFrozen(alice, account1);
    vm.prank(alice);
    governor.freeze(account1);

    assertTrue(stablecoin.frozen(account0), "testFuzz_Freeze::5");
    assertTrue(stablecoin.frozen(account1), "testFuzz_Freeze::6");

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, governor.FREEZER_ROLE())
    );
    vm.prank(admin);
    governor.freeze(admin);

    vm.stopPrank();
  }

  function testFuzz_BatchFreeze(
    address[] memory accounts
  ) public {
    uint256 length = accounts.length > 16 ? 16 : accounts.length;
    assembly {
      mstore(accounts, length)
    }

    vm.startPrank(admin);
    governor.grantRole(governor.FREEZER_ROLE(), alice);
    vm.stopPrank();

    uint256 last = 0;
    for (uint256 i = 0; i < length; i++) {
      accounts[i] = _boundAddress(accounts[i], last + 1, type(uint160).max - length + (i + 1));
      last = uint256(uint160(accounts[i]));

      assertFalse(stablecoin.frozen(accounts[i]), "testFuzz_BatchFreeze::1");
    }

    for (uint256 i = 0; i < length; i++) {
      vm.expectEmit(true, true, true, true);
      emit AccountFrozen(alice, accounts[i]);
    }

    vm.prank(alice);
    governor.batchFreeze(accounts);

    for (uint256 i = 0; i < length; i++) {
      assertTrue(stablecoin.frozen(accounts[i]), "testFuzz_BatchFreeze::2");
    }

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, governor.FREEZER_ROLE())
    );
    vm.prank(admin);
    governor.batchFreeze(accounts);

    vm.stopPrank();
  }

  function testFuzz_Unfreeze(address account0, address account1) public {
    account0 = _boundAddress(account0, 1, type(uint160).max - 1);
    account1 = _boundAddress(account1, uint160(account0) + 1, type(uint160).max);

    vm.startPrank(admin);
    governor.grantRole(governor.FREEZER_ROLE(), admin);
    governor.grantRole(governor.UNFREEZER_ROLE(), alice);

    governor.freeze(account0);
    governor.freeze(account1);
    vm.stopPrank();

    assertTrue(stablecoin.frozen(account0), "testFuzz_Unfreeze::1");
    assertTrue(stablecoin.frozen(account1), "testFuzz_Unfreeze::2");

    vm.expectEmit(true, true, true, true);
    emit AccountUnfrozen(alice, account0);
    vm.prank(alice);
    governor.unfreeze(account0);

    assertFalse(stablecoin.frozen(account0), "testFuzz_Unfreeze::3");
    assertTrue(stablecoin.frozen(account1), "testFuzz_Unfreeze::4");

    vm.expectEmit(true, true, true, true);
    emit AccountUnfrozen(alice, account1);
    vm.prank(alice);
    governor.unfreeze(account1);

    assertFalse(stablecoin.frozen(account0), "testFuzz_Unfreeze::5");
    assertFalse(stablecoin.frozen(account1), "testFuzz_Unfreeze::6");

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, governor.UNFREEZER_ROLE())
    );
    vm.prank(admin);
    governor.unfreeze(admin);

    vm.stopPrank();
  }

  function testFuzz_BatchUnfreeze(
    address[] memory accounts
  ) public {
    uint256 length = accounts.length > 16 ? 16 : accounts.length;
    assembly {
      mstore(accounts, length)
    }

    vm.startPrank(admin);
    governor.grantRole(governor.FREEZER_ROLE(), admin);
    governor.grantRole(governor.UNFREEZER_ROLE(), alice);

    uint256 last = 0;
    for (uint256 i = 0; i < length; i++) {
      accounts[i] = _boundAddress(accounts[i], last + 1, type(uint160).max - length + (i + 1));
      last = uint256(uint160(accounts[i]));

      governor.freeze(accounts[i]);
      assertTrue(stablecoin.frozen(accounts[i]), "testFuzz_BatchUnfreeze::1");
    }
    vm.stopPrank();

    for (uint256 i = 0; i < length; i++) {
      vm.expectEmit(true, true, true, true);
      emit AccountUnfrozen(alice, accounts[i]);
    }

    vm.prank(alice);
    governor.batchUnfreeze(accounts);

    for (uint256 i = 0; i < length; i++) {
      assertFalse(stablecoin.frozen(accounts[i]), "testFuzz_BatchUnfreeze::2");
    }

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, governor.UNFREEZER_ROLE())
    );
    vm.prank(admin);
    governor.batchUnfreeze(accounts);

    vm.stopPrank();
  }

  function testFuzz_Pause() public {
    vm.startPrank(admin);
    governor.grantRole(governor.PAUSER_ROLE(), alice);
    vm.stopPrank();

    assertFalse(stablecoin.paused(), "testFuzz_Pause::1");

    vm.expectEmit(true, true, true, true);
    emit ContractPaused(alice);
    vm.prank(alice);
    governor.pause();

    assertTrue(stablecoin.paused(), "testFuzz_Pause::2");

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, governor.PAUSER_ROLE())
    );
    vm.prank(admin);
    governor.pause();

    vm.stopPrank();
  }

  function testFuzz_Unpause() public {
    vm.startPrank(admin);
    governor.grantRole(governor.PAUSER_ROLE(), admin);
    governor.grantRole(governor.UNPAUSER_ROLE(), alice);

    governor.pause();
    vm.stopPrank();

    assertTrue(stablecoin.paused(), "testFuzz_Unpause::1");

    vm.expectEmit(true, true, true, true);
    emit ContractUnpaused(alice);
    vm.prank(alice);
    governor.unpause();

    assertFalse(stablecoin.paused(), "testFuzz_Unpause::2");

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, governor.UNPAUSER_ROLE())
    );
    vm.prank(admin);
    governor.unpause();

    vm.stopPrank();
  }

  function testFuzz_TransferOwnership(
    address newOwner
  ) public {
    newOwner = _boundAddress(newOwner, 1, type(uint160).max - 1);

    assertEq(stablecoin.owner(), address(governor), "testFuzz_TransferOwnership::1");
    assertEq(stablecoin.pendingOwner(), address(0), "testFuzz_TransferOwnership::2");

    vm.expectEmit(true, true, true, true);
    emit OwnershipTransferred(admin, newOwner);
    vm.prank(admin);
    governor.transferOwnership(newOwner);

    assertEq(stablecoin.pendingOwner(), newOwner, "testFuzz_TransferOwnership::3");

    vm.prank(newOwner);
    stablecoin.acceptOwnership();

    assertEq(stablecoin.owner(), newOwner, "testFuzz_TransferOwnership::4");

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, alice, governor.DEFAULT_ADMIN_ROLE()
      )
    );
    vm.prank(alice);
    governor.transferOwnership(alice);

    vm.stopPrank();
  }

  function testFuzz_AcceptOwnership() public {
    vm.startPrank(admin);
    governor.transferOwnership(admin);
    stablecoin.acceptOwnership();
    stablecoin.transferOwnership(address(governor));
    vm.stopPrank();

    assertEq(stablecoin.owner(), admin, "testFuzz_AcceptOwnership::1");
    assertEq(stablecoin.pendingOwner(), address(governor), "testFuzz_AcceptOwnership::2");

    vm.expectEmit(true, true, true, true);
    emit OwnershipTransferred(admin, address(governor));
    vm.prank(admin);
    governor.acceptOwnership();

    assertEq(stablecoin.owner(), address(governor), "testFuzz_AcceptOwnership::3");
    assertEq(stablecoin.pendingOwner(), address(0), "testFuzz_AcceptOwnership::4");

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, alice, governor.DEFAULT_ADMIN_ROLE()
      )
    );
    vm.prank(alice);
    governor.acceptOwnership();

    vm.stopPrank();
  }

  function testFuzz_RecoverERC20(address to, uint256 amount) public {
    to = _boundAddress(to, 1, type(uint160).max - 1);
    amount = bound(amount, 1, type(uint256).max - 1);
    vm.assume(to != address(governor));

    vm.startPrank(admin);
    governor.grantRole(governor.RECOVERY_ROLE(), alice);
    vm.stopPrank();

    assertEq(stablecoin.balanceOf(address(governor)), 0, "testFuzz_RecoverERC20::1");

    vm.prank(address(governor));
    stablecoin.mint(amount);

    assertEq(stablecoin.balanceOf(address(governor)), amount, "testFuzz_RecoverERC20::2");

    vm.expectEmit(true, true, true, true);
    emit TokensRecovered(alice, address(stablecoin), to, amount);
    vm.prank(alice);
    governor.recoverERC20(address(stablecoin), to, amount);

    assertEq(stablecoin.balanceOf(address(governor)), 0, "testFuzz_RecoverERC20::3");
    assertEq(stablecoin.balanceOf(to), amount, "testFuzz_RecoverERC20::4");

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, governor.RECOVERY_ROLE())
    );
    vm.prank(admin);
    governor.recoverERC20(address(stablecoin), to, amount);

    vm.expectRevert(ITokenGovernor.ZeroAddressNotAllowed.selector);
    vm.prank(alice);
    governor.recoverERC20(address(stablecoin), address(0), amount);

    vm.stopPrank();
  }

  function test_RecoverGovernedTokenERC20(
    uint256 amount
  ) public {
    vm.startPrank(admin);
    governor.grantRole(governor.RECOVERY_ROLE(), alice);
    vm.stopPrank();

    vm.startPrank(address(governor));
    stablecoin.mint(amount);
    stablecoin.transfer(address(stablecoin), amount);
    vm.stopPrank();

    assertEq(stablecoin.balanceOf(address(stablecoin)), amount, "test_RecoverGovernedTokenERC20::1");

    vm.expectEmit(true, true, true, true);
    emit GovernedTokensRecovered(alice, address(stablecoin), address(this), amount);

    vm.prank(alice);
    governor.recoverGovernedTokenERC20(address(stablecoin), address(this), amount);

    assertEq(stablecoin.balanceOf(address(this)), amount, "test_RecoverGovernedTokenERC20::2");
    assertEq(stablecoin.balanceOf(address(stablecoin)), 0, "test_RecoverGovernedTokenERC20::3");

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, governor.RECOVERY_ROLE())
    );
    vm.prank(admin);
    governor.recoverGovernedTokenERC20(address(stablecoin), address(this), amount);
  }

  function testFuzz_DrainFrozenAccount(address account, uint256 amount) public {
    account = _boundAddress(account, 1, type(uint160).max - 1);
    amount = bound(amount, 1, type(uint256).max - 1);

    vm.startPrank(address(governor));
    stablecoin.mint(amount);
    stablecoin.transfer(account, amount);
    vm.stopPrank();

    assertEq(stablecoin.balanceOf(account), amount, "testFuzz_DrainFrozenAccount::1");

    vm.startPrank(admin);
    governor.grantRole(governor.FREEZER_ROLE(), admin);

    governor.freeze(account);

    assertTrue(stablecoin.frozen(account), "testFuzz_DrainFrozenAccount::2");

    vm.expectEmit(true, true, true, true);
    emit FrozenAccountDrained(admin, account);

    governor.drainFrozenAccount(account);

    assertEq(stablecoin.balanceOf(account), 0, "testFuzz_DrainFrozenAccount::3");

    vm.stopPrank();
  }

  function testFuzz_BatchDrainFrozenAccounts(
    address[] memory accounts
  ) public {
    uint256 length = accounts.length > 16 ? 16 : accounts.length;
    assembly {
      mstore(accounts, length)
    }

    vm.startPrank(admin);
    governor.grantRole(governor.FREEZER_ROLE(), admin);

    uint256 last = 0;
    for (uint256 i = 0; i < length; i++) {
      accounts[i] = _boundAddress(accounts[i], last + 1, type(uint160).max - length + (i + 1));
      last = uint256(uint160(accounts[i]));

      governor.freeze(accounts[i]);
      assertTrue(stablecoin.frozen(accounts[i]), "testFuzz_BatchDrainFrozenAccounts::1");
    }

    for (uint256 i = 0; i < length; i++) {
      vm.expectEmit(true, true, true, true);
      emit FrozenAccountDrained(admin, accounts[i]);
    }

    governor.batchDrainFrozenAccounts(accounts);

    for (uint256 i = 0; i < length; i++) {
      assertEq(stablecoin.balanceOf(accounts[i]), 0, "testFuzz_BatchDrainFrozenAccounts::2");
    }

    vm.stopPrank();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, alice, governor.DEFAULT_ADMIN_ROLE()
      )
    );
    vm.prank(alice);
    governor.batchDrainFrozenAccounts(accounts);
  }

  function test_ExecuteTokenFunction() public {
    vm.expectEmit(true, true, true, true);
    emit TokenFunctionExecuted(admin, abi.encodeWithSelector(IGovernedToken.mint.selector, 1e18), abi.encode(true));
    vm.prank(admin);
    governor.executeTokenFunction(abi.encodeWithSelector(IGovernedToken.mint.selector, 1e18));

    assertEq(stablecoin.balanceOf(address(governor)), 1e18, "test_ExecuteTokenFunction::1");

    vm.expectEmit(true, true, true, true);
    emit TokenFunctionExecuted(admin, abi.encodeWithSelector(IGovernedToken.transferOwnership.selector, admin), "");
    vm.prank(admin);
    governor.executeTokenFunction(abi.encodeWithSelector(IGovernedToken.transferOwnership.selector, admin));

    assertEq(stablecoin.owner(), address(governor), "test_ExecuteTokenFunction::2");
    assertEq(stablecoin.pendingOwner(), admin, "test_ExecuteTokenFunction::3");

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, alice, governor.DEFAULT_ADMIN_ROLE()
      )
    );
    vm.prank(alice);
    governor.executeTokenFunction("");

    bytes memory error = abi.encodeWithSignature("Error(string)", "Unsupported");

    vm.expectRevert(abi.encodeWithSelector(ITokenGovernor.CallFailed.selector, error));
    vm.prank(admin);
    governor.executeTokenFunction(abi.encodeWithSelector(Stablecoin.renounceOwnership.selector));

    vm.stopPrank();
  }

  function test_RevertOnMintOrBurnReturningFalse() public {
    vm.startPrank(admin);
    governor = new TokenGovernor(address(this), 0, admin);

    governor.grantRole(governor.MINTER_ROLE(), alice);
    governor.grantRole(governor.BURNER_ROLE(), bob);
    governor.grantRole(governor.BRIDGE_MINTER_OR_BURNER_ROLE(), bridge);
    vm.stopPrank();

    _revert = false;
    _returnData = abi.encode(false);

    vm.expectRevert(ITokenGovernor.MintFailed.selector);
    vm.prank(alice);
    governor.mint(1);

    vm.expectRevert(ITokenGovernor.MintFailed.selector);
    vm.prank(alice);
    governor.mint(address(1), 1);

    vm.expectRevert(ITokenGovernor.MintFailed.selector);
    vm.prank(bridge);
    governor.mint(1);

    vm.expectRevert(ITokenGovernor.MintFailed.selector);
    vm.prank(bridge);
    governor.mint(address(1), 1);

    vm.expectRevert(ITokenGovernor.BurnFailed.selector);
    vm.prank(bob);
    governor.burn(1);

    vm.expectRevert(ITokenGovernor.BurnFailed.selector);
    vm.prank(bob);
    governor.burnFrom(address(1), 1);

    vm.expectRevert(ITokenGovernor.BurnFailed.selector);
    vm.prank(bridge);
    governor.burn(1);

    vm.expectRevert(ITokenGovernor.BurnFailed.selector);
    vm.prank(bridge);
    governor.burnFrom(address(1), 1);
  }

  function test_RevertOnCheckMintOrBurnReverting() public {
    vm.startPrank(admin);
    governor.grantRole(governor.CHECKER_ADMIN_ROLE(), admin);
    governor.setChecker(address(this));

    governor.grantRole(governor.MINTER_ROLE(), alice);
    governor.grantRole(governor.BURNER_ROLE(), bob);
    governor.grantRole(governor.BRIDGE_MINTER_OR_BURNER_ROLE(), bridge);
    vm.stopPrank();

    _revert = true;
    _returnData = abi.encodeWithSignature("Error(string)", "Not allowed");

    vm.expectRevert("Not allowed");
    vm.prank(alice);
    governor.mint(1);

    vm.expectRevert("Not allowed");
    vm.prank(alice);
    governor.mint(address(1), 1);

    vm.expectRevert("Not allowed");
    vm.prank(bridge);
    governor.mint(1);

    vm.expectRevert("Not allowed");
    vm.prank(bridge);
    governor.mint(address(1), 1);

    vm.expectRevert("Not allowed");
    vm.prank(bob);
    governor.burn(1);

    vm.expectRevert("Not allowed");
    vm.prank(bob);
    governor.burnFrom(address(1), 1);

    vm.expectRevert("Not allowed");
    vm.prank(bridge);
    governor.burn(1);

    vm.expectRevert("Not allowed");
    vm.prank(bridge);
    governor.burnFrom(address(1), 1);

    bytes memory error = abi.encodeWithSignature("CustomError()");
    _revert = true;
    _returnData = error;

    vm.expectRevert(error);
    vm.prank(alice);
    governor.mint(1);

    vm.expectRevert(error);
    vm.prank(alice);
    governor.mint(address(1), 1);

    vm.expectRevert(error);
    vm.prank(bridge);
    governor.mint(1);

    vm.expectRevert(error);
    vm.prank(bridge);
    governor.mint(address(1), 1);

    vm.expectRevert(error);
    vm.prank(bob);
    governor.burn(1);

    vm.expectRevert(error);
    vm.prank(bob);
    governor.burnFrom(address(1), 1);

    vm.expectRevert(error);
    vm.prank(bridge);
    governor.burn(1);

    vm.expectRevert(error);
    vm.prank(bridge);
    governor.burnFrom(address(1), 1);
  }

  bool _revert;
  bytes _returnData;

  fallback() external {
    if (msg.sig != IERC20.transferFrom.selector && msg.sig != IERC20.transfer.selector) {
      bytes memory data = _returnData;

      if (_revert) {
        assembly {
          log0(add(data, 0x20), mload(data))
          revert(add(data, 0x20), mload(data))
        }
      } else {
        assembly {
          return(add(data, 0x20), mload(data))
        }
      }
    } else {
      assembly {
        mstore(0, 1)
        return(0, 0x20)
      }
    }
  }

  function _boundAddress(address addr, uint256 start, uint256 end) internal pure returns (address) {
    return address(uint160(bound(uint256(uint160(addr)), start, end)));
  }
}
