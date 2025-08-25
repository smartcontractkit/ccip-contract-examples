// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../checkers/CheckerCounter.sol";

contract CheckerCounterTest is Test {
  CheckerCounter public checker;

  function setUp() public {
    checker = new CheckerCounter(address(this));
  }

  struct Minter {
    address minter;
    uint256 amount;
  }

  struct Burner {
    address burner;
    uint256 amount;
  }

  event Minted(address indexed minter, uint256 amount, uint256 totalMinterMinted, uint256 totalGlobalMinted);
  event Burned(address indexed burner, uint256 amount, uint256 totalBurnerBurned, uint256 totalGlobalBurned);

  mapping(address => uint256) public mintCount;
  mapping(address => uint256) public burnCount;

  function test_Constructor() public {
    assertEq(checker.getGovernor(), address(this), "test_Constructor::1");

    vm.expectRevert(ICheckerCounter.ZeroAddressNotAllowed.selector);
    new CheckerCounter(address(0));
  }

  function testFuzz_CheckMintBurn(Minter[] memory minters, Burner[] memory burners) public {
    uint256 sum = 0;
    for (uint256 i = 0; i < minters.length; i++) {
      minters[i].amount = bound(minters[i].amount, 1, type(uint256).max - (sum - i + minters.length));
      sum += minters[i].amount;
    }
    sum = 0;
    for (uint256 i = 0; i < burners.length; i++) {
      burners[i].amount = bound(burners[i].amount, 1, type(uint256).max - (sum - i + burners.length));
      sum += burners[i].amount;
    }

    sum = 0;
    for (uint256 i = 0; i < minters.length; i++) {
      sum += minters[i].amount;
      mintCount[minters[i].minter] += minters[i].amount;

      vm.expectEmit(true, true, true, true);
      emit Minted(minters[i].minter, minters[i].amount, mintCount[minters[i].minter], sum);
      checker.checkMint(address(0), minters[i].amount, minters[i].minter, true);

      assertEq(checker.getTotalMinted(), sum, "testFuzz_CheckMintBurn::1");
      assertEq(checker.getTotalMintedBy(minters[i].minter), mintCount[minters[i].minter], "testFuzz_CheckMintBurn::2");
    }

    sum = 0;
    for (uint256 i = 0; i < burners.length; i++) {
      sum += burners[i].amount;
      burnCount[burners[i].burner] += burners[i].amount;

      vm.expectEmit(true, true, true, true);
      emit Burned(burners[i].burner, burners[i].amount, burnCount[burners[i].burner], sum);
      checker.checkBurn(address(0), burners[i].amount, burners[i].burner, true);

      assertEq(checker.getTotalBurned(), sum, "testFuzz_CheckMintBurn::3");
      assertEq(checker.getTotalBurnedBy(burners[i].burner), burnCount[burners[i].burner], "testFuzz_CheckMintBurn::4");
    }

    address[] memory mintersList = checker.getMinters(0, minters.length);
    assertEq(mintersList.length, checker.getMintersCount(), "testFuzz_CheckMintBurn::5");
    for (uint256 i = 0; i < mintersList.length; i++) {
      assertGt(mintCount[mintersList[i]], 0, "testFuzz_CheckMintBurn::6");
    }

    address[] memory mintersList0to5 = checker.getMinters(0, 5);
    for (uint256 i = 0; i < mintersList0to5.length; i++) {
      assertEq(mintersList0to5[i], mintersList[i], "testFuzz_CheckMintBurn::7");
    }

    address[] memory mintersList5to10 = checker.getMinters(5, 10);
    for (uint256 i = 0; i < mintersList5to10.length; i++) {
      assertEq(mintersList5to10[i], mintersList[i + 5], "testFuzz_CheckMintBurn::8");
    }

    address[] memory burnersList = checker.getBurners(0, burners.length);
    assertEq(burnersList.length, checker.getBurnersCount(), "testFuzz_CheckMintBurn::9");
    for (uint256 i = 0; i < burnersList.length; i++) {
      assertGt(burnCount[burnersList[i]], 0, "testFuzz_CheckMintBurn::10");
    }

    address[] memory burnersList0to5 = checker.getBurners(0, 5);
    for (uint256 i = 0; i < burnersList0to5.length; i++) {
      assertEq(burnersList0to5[i], burnersList[i], "testFuzz_CheckMintBurn::11");
    }

    address[] memory burnersList5to10 = checker.getBurners(5, 10);
    for (uint256 i = 0; i < burnersList5to10.length; i++) {
      assertEq(burnersList5to10[i], burnersList[i + 5], "testFuzz_CheckMintBurn::12");
    }
  }

  function test_Revert_OnlyGovernor() public {
    vm.startPrank(address(1));

    vm.expectRevert(ICheckerCounter.OnlyGovernor.selector);
    checker.checkMint(address(0), 1, address(0), true);

    vm.expectRevert(ICheckerCounter.OnlyGovernor.selector);
    checker.checkBurn(address(0), 1, address(0), true);

    vm.stopPrank();
  }

  function test_Revert_InvalidRange() public {
    vm.expectRevert(abi.encodeWithSelector(ICheckerCounter.InvalidRange.selector, 1, 0));
    checker.getMinters(1, 0);

    vm.expectRevert(abi.encodeWithSelector(ICheckerCounter.InvalidRange.selector, 1, 0));
    checker.getBurners(1, 0);
  }
}
