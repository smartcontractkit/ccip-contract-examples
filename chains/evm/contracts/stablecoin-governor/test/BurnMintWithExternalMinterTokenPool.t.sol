// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "./Utils.t.sol";

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";
import {BurnMintTokenPool} from "@chainlink/contracts-ccip/contracts/pools/BurnMintTokenPool.sol";
import {BurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/BurnMintERC20.sol";

import "../BurnMintWithExternalMinterTokenPool.sol";

import {TokenGovernor} from "../TokenGovernor.sol";
import "../checkers/CheckerCounter.sol";
import {Stablecoin} from "./utils/Stablecoin.sol";

contract BurnMintWithExternalMinterTokenPoolTest is Utils {
  struct Src {
    CCIPChain chain;
    BurnMintWithExternalMinterTokenPool tokenPool;
    TokenGovernor governor;
    CheckerCounter checker;
    Stablecoin stablecoin;
  }

  struct Dst {
    CCIPChain chain;
    BurnMintTokenPool tokenPool;
    BurnMintERC20 erc20;
  }

  Src src;
  Dst dst;

  function setUp() public {
    _addChains(2);
    _wireAll();

    vm.startPrank(admin);

    {
      src.chain = chains[0];
      src.stablecoin = new Stablecoin();
      src.governor = new TokenGovernor(address(src.stablecoin), 0, admin);
      src.checker = new CheckerCounter(address(src.governor));

      src.tokenPool = new BurnMintWithExternalMinterTokenPool(
        address(src.governor),
        IERC20(IExternalMinter(address(src.governor)).getToken()),
        18,
        new address[](0),
        address(src.chain.armProxy),
        address(src.chain.router)
      );

      src.stablecoin.initialize("Stablecoin", "STABLE");
      src.stablecoin.transferOwnership(address(src.governor));
      src.governor.acceptOwnership();

      src.governor.grantRole(src.governor.BRIDGE_MINTER_OR_BURNER_ROLE(), address(src.tokenPool));
      src.governor.grantRole(src.governor.CHECKER_ADMIN_ROLE(), admin);
      src.governor.setChecker(address(src.checker));

      src.chain.tokenAdminRegistry.proposeAdministrator(address(src.stablecoin), admin);
      src.chain.tokenAdminRegistry.acceptAdminRole(address(src.stablecoin));
      src.chain.tokenAdminRegistry.setPool(address(src.stablecoin), address(src.tokenPool));
    }

    {
      dst.chain = chains[1];
      dst.erc20 = new BurnMintERC20("Stablecoin", "STABLE", 18, type(uint256).max, 0);

      dst.tokenPool =
        new BurnMintTokenPool(dst.erc20, 18, new address[](0), address(dst.chain.armProxy), address(dst.chain.router));

      dst.erc20.grantMintAndBurnRoles(address(dst.tokenPool));

      dst.chain.tokenAdminRegistry.proposeAdministrator(address(dst.erc20), admin);
      dst.chain.tokenAdminRegistry.acceptAdminRole(address(dst.erc20));
      dst.chain.tokenAdminRegistry.setPool(address(dst.erc20), address(dst.tokenPool));
    }

    _linkTokenPools(src.chain.chainSelector, address(src.tokenPool), dst.chain.chainSelector, address(dst.tokenPool));

    vm.stopPrank();

    vm.label(address(src.stablecoin), "Stablecoin_1");
    vm.label(address(src.governor), "Governor_1");
    vm.label(address(src.checker), "Checker_1");
    vm.label(address(src.tokenPool), "TokenPool_1");

    vm.label(address(dst.erc20), "Stablecoin_2");
    vm.label(address(dst.tokenPool), "TokenPool_2");

    vm.deal(alice, 1e18);
    vm.deal(bob, 1e18);
  }

  function test_constructor() public view {
    assertEq(src.tokenPool.typeAndVersion(), "BurnMintWithExternalMinterTokenPool 1.6.0", "test_Constructor::1");
    assertEq(address(src.tokenPool.getMinter()), address(src.governor), "test_Constructor::2");
    assertEq(address(src.tokenPool.getToken()), address(src.stablecoin), "test_Constructor::3");
    assertEq(address(src.tokenPool.getRmnProxy()), address(src.chain.armProxy), "test_Constructor::4");
    assertEq(address(src.tokenPool.getRouter()), address(src.chain.router), "test_Constructor::5");
    assertEq(src.tokenPool.getTokenDecimals(), 18, "test_Constructor::6");
  }

  function test_constructor_RevertWhen_TokenMismatch() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        BurnMintExternalMinterTokenPoolAbstract.TokenMismatch.selector,
        IERC20(address(dst.erc20)),
        IERC20(address(src.stablecoin))
      )
    );
    new BurnMintWithExternalMinterTokenPool(
      address(src.governor),
      IERC20(address(dst.erc20)),
      18,
      new address[](0),
      address(src.chain.armProxy),
      address(dst.chain.router)
    );
  }

  function test_BridgeSrcToDst() public {
    Client.EVMTokenAmount[] memory srcTokensAmounts = new Client.EVMTokenAmount[](1);
    srcTokensAmounts[0] = Client.EVMTokenAmount({token: address(src.stablecoin), amount: 1e18});

    Client.EVM2AnyMessage memory srcMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(bob),
      data: abi.encodePacked(),
      tokenAmounts: srcTokensAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 100_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = src.chain.router.getFee(dst.chain.chainSelector, srcMessage);

    vm.startPrank(admin);
    src.governor.grantRole(src.governor.MINTER_ROLE(), admin);
    src.governor.mint(alice, 1e18);
    vm.stopPrank();

    vm.startPrank(alice);
    src.stablecoin.approve(address(src.chain.router), 1e18);

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(
      dst.chain.chainSelector, address(src.stablecoin), address(onRamps[src.chain.chainSelector]), 1e18
    );

    bytes32 srcId = src.chain.router.ccipSend{value: fee}(dst.chain.chainSelector, srcMessage);
    vm.stopPrank();

    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(src.tokenPool)),
      destTokenAddress: address(dst.erc20),
      destGasAmount: 100_000,
      extraData: abi.encodePacked(),
      amount: 1e18
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: srcId,
        sourceChainSelector: src.chain.chainSelector,
        destChainSelector: dst.chain.chainSelector,
        sequenceNumber: onRamps[src.chain.chainSelector].getExpectedNextSequenceNumber(dst.chain.chainSelector),
        nonce: src.chain.nonceManager.outboundNonces(dst.chain.chainSelector, address(this))
      }),
      sender: abi.encode(address(this)),
      data: abi.encodePacked(),
      receiver: bob,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[dst.chain.chainSelector];

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));

    assertEq(src.stablecoin.balanceOf(alice), 0, "test_BridgeSrcToDst::1");
    assertEq(src.stablecoin.balanceOf(bob), 0, "test_BridgeSrcToDst::2");
    assertEq(src.stablecoin.balanceOf(address(src.governor)), 0, "test_BridgeSrcToDst::3");
    assertEq(src.stablecoin.balanceOf(address(src.tokenPool)), 0, "test_BridgeSrcToDst::4");

    assertEq(dst.erc20.balanceOf(alice), 0, "test_BridgeSrcToDst::5");
    assertEq(dst.erc20.balanceOf(bob), 1e18, "test_BridgeSrcToDst::6");
    assertEq(dst.erc20.balanceOf(address(dst.tokenPool)), 0, "test_BridgeSrcToDst::7");
  }

  function test_BridgeDstToSrc() public {
    Client.EVMTokenAmount[] memory srcTokensAmounts = new Client.EVMTokenAmount[](1);
    srcTokensAmounts[0] = Client.EVMTokenAmount({token: address(dst.erc20), amount: 1e18});

    Client.EVM2AnyMessage memory srcMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(alice),
      data: abi.encodePacked(),
      tokenAmounts: srcTokensAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 300_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = dst.chain.router.getFee(src.chain.chainSelector, srcMessage);

    vm.startPrank(admin);
    dst.erc20.grantRole(dst.erc20.MINTER_ROLE(), admin);
    dst.erc20.mint(bob, 1e18);
    vm.stopPrank();

    vm.startPrank(bob);
    dst.erc20.approve(address(dst.chain.router), 1e18);
    bytes32 dstId = dst.chain.router.ccipSend{value: fee}(src.chain.chainSelector, srcMessage);
    vm.stopPrank();

    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(dst.tokenPool)),
      destTokenAddress: address(src.stablecoin),
      destGasAmount: 300_000,
      extraData: abi.encodePacked(),
      amount: 1e18
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: dstId,
        sourceChainSelector: dst.chain.chainSelector,
        destChainSelector: src.chain.chainSelector,
        sequenceNumber: onRamps[dst.chain.chainSelector].getExpectedNextSequenceNumber(src.chain.chainSelector),
        nonce: dst.chain.nonceManager.outboundNonces(src.chain.chainSelector, address(this))
      }),
      sender: abi.encode(address(this)),
      data: abi.encodePacked(),
      receiver: alice,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[src.chain.chainSelector];

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(
      dst.chain.chainSelector, address(src.stablecoin), address(offRamps[src.chain.chainSelector]), alice, 1e18
    );

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));

    assertEq(dst.erc20.balanceOf(alice), 0, "test_BridgeDstToSrc::1");
    assertEq(dst.erc20.balanceOf(bob), 0, "test_BridgeDstToSrc::2");
    assertEq(dst.erc20.balanceOf(address(dst.tokenPool)), 0, "test_BridgeDstToSrc::3");

    assertEq(src.stablecoin.balanceOf(alice), 1e18, "test_BridgeDstToSrc::4");
    assertEq(src.stablecoin.balanceOf(bob), 0, "test_BridgeDstToSrc::5");
    assertEq(src.stablecoin.balanceOf(address(src.governor)), 0, "test_BridgeDstToSrc::6");
    assertEq(src.stablecoin.balanceOf(address(src.tokenPool)), 0, "test_BridgeDstToSrc::7");
  }
}
