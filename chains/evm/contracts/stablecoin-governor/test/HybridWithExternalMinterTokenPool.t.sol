// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "./Utils.t.sol";

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";
import {BurnMintTokenPool} from "@chainlink/contracts-ccip/contracts/pools/BurnMintTokenPool.sol";
import {BurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/BurnMintERC20.sol";
import {IERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {HybridTokenPoolAbstract} from "../../stablecoin-governor/HybridTokenPoolAbstract.sol";
import {HybridWithExternalMinterTokenPool} from "../../stablecoin-governor/HybridWithExternalMinterTokenPool.sol";
import {TokenGovernor} from "../../stablecoin-governor/TokenGovernor.sol";
import {CheckerCounter} from "../checkers/CheckerCounter.sol";
import {Stablecoin} from "./utils/Stablecoin.sol";

contract HybridWithExternalMinterTokenPoolTest is Utils {
  struct ManagerChain {
    CCIPChain chain;
    HybridWithExternalMinterTokenPool tokenPool;
    TokenGovernor governor;
    CheckerCounter checker;
    Stablecoin stablecoin;
  }

  struct DstChain {
    CCIPChain chain;
    BurnMintTokenPool tokenPool;
    BurnMintERC20 token;
  }

  ManagerChain managerChain;
  DstChain dstChainBnM1;
  DstChain dstChainBnM2;
  DstChain dstChainLnR1;
  DstChain dstChainLnR2;

  function setUp() public {
    _addChains(5);
    _wireAll();

    managerChain.chain = chains[0];
    dstChainBnM1.chain = chains[1];
    dstChainBnM2.chain = chains[2];
    dstChainLnR1.chain = chains[3];
    dstChainLnR2.chain = chains[4];

    vm.startPrank(admin);

    // Manager
    {
      managerChain.stablecoin = new Stablecoin();
      managerChain.governor = new TokenGovernor(address(managerChain.stablecoin), 0, admin);
      managerChain.checker = new CheckerCounter(address(managerChain.governor));

      managerChain.tokenPool = new HybridWithExternalMinterTokenPool(
        address(managerChain.governor),
        IERC20(address(managerChain.stablecoin)),
        18,
        new address[](0),
        address(managerChain.chain.armProxy),
        address(managerChain.chain.router)
      );

      managerChain.stablecoin.initialize("Stablecoin", "STABLE");
      managerChain.stablecoin.transferOwnership(address(managerChain.governor));
      managerChain.governor.acceptOwnership();

      managerChain.governor.grantRole(
        managerChain.governor.BRIDGE_MINTER_OR_BURNER_ROLE(), address(managerChain.tokenPool)
      );
      managerChain.governor.grantRole(managerChain.governor.CHECKER_ADMIN_ROLE(), admin);
      managerChain.governor.setChecker(address(managerChain.checker));

      managerChain.tokenPool.setRebalancer(admin);

      managerChain.chain.tokenAdminRegistry.proposeAdministrator(address(managerChain.stablecoin), admin);
      managerChain.chain.tokenAdminRegistry.acceptAdminRole(address(managerChain.stablecoin));
      managerChain.chain.tokenAdminRegistry.setPool(address(managerChain.stablecoin), address(managerChain.tokenPool));
    }

    // Burn and Mint Chain A
    {
      dstChainBnM1.token = new BurnMintERC20("Stablecoin", "STABLE", 18, type(uint256).max, 0);
      dstChainBnM1.tokenPool = new BurnMintTokenPool(
        dstChainBnM1.token,
        18,
        new address[](0),
        address(dstChainBnM1.chain.armProxy),
        address(dstChainBnM1.chain.router)
      );

      dstChainBnM1.token.grantMintAndBurnRoles(address(dstChainBnM1.tokenPool));

      dstChainBnM1.chain.tokenAdminRegistry.proposeAdministrator(address(dstChainBnM1.token), admin);
      dstChainBnM1.chain.tokenAdminRegistry.acceptAdminRole(address(dstChainBnM1.token));
      dstChainBnM1.chain.tokenAdminRegistry.setPool(address(dstChainBnM1.token), address(dstChainBnM1.tokenPool));
    }

    // Burn and Mint Chain B
    {
      dstChainBnM2.token = new BurnMintERC20("Stablecoin", "STABLE", 18, type(uint256).max, 0);
      dstChainBnM2.tokenPool = new BurnMintTokenPool(
        dstChainBnM2.token,
        18,
        new address[](0),
        address(dstChainBnM2.chain.armProxy),
        address(dstChainBnM2.chain.router)
      );

      dstChainBnM2.token.grantMintAndBurnRoles(address(dstChainBnM2.tokenPool));

      dstChainBnM2.chain.tokenAdminRegistry.proposeAdministrator(address(dstChainBnM2.token), admin);
      dstChainBnM2.chain.tokenAdminRegistry.acceptAdminRole(address(dstChainBnM2.token));
      dstChainBnM2.chain.tokenAdminRegistry.setPool(address(dstChainBnM2.token), address(dstChainBnM2.tokenPool));
    }

    // Lock and Release Chain A
    {
      dstChainLnR1.token = new BurnMintERC20("Stablecoin", "STABLE", 18, type(uint256).max, 0);
      dstChainLnR1.tokenPool = new BurnMintTokenPool(
        dstChainLnR1.token,
        18,
        new address[](0),
        address(dstChainLnR1.chain.armProxy),
        address(dstChainLnR1.chain.router)
      );

      dstChainLnR1.token.grantMintAndBurnRoles(address(dstChainLnR1.tokenPool));

      dstChainLnR1.chain.tokenAdminRegistry.proposeAdministrator(address(dstChainLnR1.token), admin);
      dstChainLnR1.chain.tokenAdminRegistry.acceptAdminRole(address(dstChainLnR1.token));
      dstChainLnR1.chain.tokenAdminRegistry.setPool(address(dstChainLnR1.token), address(dstChainLnR1.tokenPool));
    }

    // Lock and Release Chain B
    {
      dstChainLnR2.token = new BurnMintERC20("Stablecoin", "STABLE", 18, type(uint256).max, 0);
      dstChainLnR2.tokenPool = new BurnMintTokenPool(
        dstChainLnR2.token,
        18,
        new address[](0),
        address(dstChainLnR2.chain.armProxy),
        address(dstChainLnR2.chain.router)
      );

      dstChainLnR2.token.grantMintAndBurnRoles(address(dstChainLnR2.tokenPool));

      dstChainLnR2.chain.tokenAdminRegistry.proposeAdministrator(address(dstChainLnR2.token), admin);
      dstChainLnR2.chain.tokenAdminRegistry.acceptAdminRole(address(dstChainLnR2.token));
      dstChainLnR2.chain.tokenAdminRegistry.setPool(address(dstChainLnR2.token), address(dstChainLnR2.tokenPool));
    }

    vm.stopPrank();

    // Link manager and all chains
    _linkTokenPools(
      managerChain.chain.chainSelector,
      address(managerChain.tokenPool),
      dstChainBnM1.chain.chainSelector,
      address(dstChainBnM1.tokenPool)
    );
    _linkTokenPools(
      managerChain.chain.chainSelector,
      address(managerChain.tokenPool),
      dstChainBnM2.chain.chainSelector,
      address(dstChainBnM2.tokenPool)
    );
    _linkTokenPools(
      managerChain.chain.chainSelector,
      address(managerChain.tokenPool),
      dstChainLnR1.chain.chainSelector,
      address(dstChainLnR1.tokenPool)
    );
    _linkTokenPools(
      managerChain.chain.chainSelector,
      address(managerChain.tokenPool),
      dstChainLnR2.chain.chainSelector,
      address(dstChainLnR2.tokenPool)
    );

    // Link BnM chains to each other
    _linkTokenPools(
      dstChainBnM1.chain.chainSelector,
      address(dstChainBnM1.tokenPool),
      dstChainBnM2.chain.chainSelector,
      address(dstChainBnM2.tokenPool)
    );

    // Link LnR chains to each other
    _linkTokenPools(
      dstChainLnR1.chain.chainSelector,
      address(dstChainLnR1.tokenPool),
      dstChainLnR2.chain.chainSelector,
      address(dstChainLnR2.tokenPool)
    );

    // Update the BnM pool
    {
      HybridTokenPoolAbstract.GroupUpdate[] memory updates = new HybridTokenPoolAbstract.GroupUpdate[](2);
      updates[0] = HybridTokenPoolAbstract.GroupUpdate({
        remoteChainSelector: dstChainBnM1.chain.chainSelector,
        group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
        remoteChainSupply: 0
      });
      updates[1] = HybridTokenPoolAbstract.GroupUpdate({
        remoteChainSelector: dstChainBnM2.chain.chainSelector,
        group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
        remoteChainSupply: 0
      });

      vm.prank(admin);
      managerChain.tokenPool.updateGroups(updates);
    }

    vm.label(address(managerChain.stablecoin), "STABLE_1");
    vm.label(address(managerChain.tokenPool), "TokenPool_1");
    vm.label(address(managerChain.governor), "TokenGovernor_1");
    vm.label(address(managerChain.checker), "CheckerCounter_1");

    vm.label(address(dstChainBnM1.token), "STABLE_2");
    vm.label(address(dstChainBnM1.tokenPool), "TokenPool_2");

    vm.label(address(dstChainBnM2.token), "STABLE_3");
    vm.label(address(dstChainBnM2.tokenPool), "TokenPool_3");

    vm.label(address(dstChainLnR1.token), "STABLE_4");
    vm.label(address(dstChainLnR1.tokenPool), "TokenPool_4");

    vm.label(address(dstChainLnR2.token), "STABLE_5");
    vm.label(address(dstChainLnR2.tokenPool), "TokenPool_5");

    vm.deal(alice, 1e18);
    vm.deal(bob, 1e18);
  }

  function test_constructor() public view {
    assertEq(managerChain.tokenPool.typeAndVersion(), "HybridWithExternalMinterTokenPool 1.6.0", "test_Constructor::1");
    assertEq(managerChain.tokenPool.getRebalancer(), address(admin), "test_Constructor::2");
    assertEq(managerChain.tokenPool.getMinter(), address(managerChain.governor), "test_Constructor::3");
    assertEq(address(managerChain.tokenPool.getToken()), address(managerChain.stablecoin), "test_Constructor::4");
    assertEq(managerChain.tokenPool.getTokenDecimals(), 18, "test_Constructor::5");
    assertEq(managerChain.tokenPool.getRmnProxy(), address(managerChain.chain.armProxy), "test_Constructor::6");
    assertEq(managerChain.tokenPool.getRouter(), address(managerChain.chain.router), "test_Constructor::7");
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainBnM1.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT),
      "test_Constructor::8"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainBnM2.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT),
      "test_Constructor::9"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainLnR1.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE),
      "test_Constructor::10"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainLnR2.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE),
      "test_Constructor::11"
    );
  }

  function test_constructor_RevertWhen_TokenMismatch() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        HybridTokenPoolAbstract.TokenMismatch.selector,
        IERC20(address(dstChainBnM1.token)),
        IERC20(address(managerChain.stablecoin))
      )
    );
    new HybridWithExternalMinterTokenPool(
      address(managerChain.governor),
      IERC20(address(dstChainBnM1.token)),
      18,
      new address[](0),
      address(managerChain.chain.armProxy),
      address(managerChain.chain.router)
    );
  }

  function test_BridgeManagerToBnM1() public {
    Client.EVMTokenAmount[] memory srcTokensAmounts = new Client.EVMTokenAmount[](1);
    srcTokensAmounts[0] = Client.EVMTokenAmount({token: address(managerChain.stablecoin), amount: 1e18});

    Client.EVM2AnyMessage memory srcMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(bob),
      data: abi.encodePacked(),
      tokenAmounts: srcTokensAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 100_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = managerChain.chain.router.getFee(dstChainBnM1.chain.chainSelector, srcMessage);

    vm.startPrank(admin);
    managerChain.governor.grantRole(managerChain.governor.MINTER_ROLE(), admin);
    managerChain.governor.mint(alice, 1e18);
    vm.stopPrank();

    vm.startPrank(alice);
    managerChain.stablecoin.approve(address(managerChain.chain.router), 1e18);

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(
      dstChainBnM1.chain.chainSelector,
      address(managerChain.stablecoin),
      address(onRamps[managerChain.chain.chainSelector]),
      1e18
    );

    bytes32 srcId = managerChain.chain.router.ccipSend{value: fee}(dstChainBnM1.chain.chainSelector, srcMessage);
    vm.stopPrank();

    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(managerChain.tokenPool)),
      destTokenAddress: address(dstChainBnM1.token),
      destGasAmount: 100_000,
      extraData: abi.encodePacked(),
      amount: 1e18
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: srcId,
        sourceChainSelector: managerChain.chain.chainSelector,
        destChainSelector: dstChainBnM1.chain.chainSelector,
        sequenceNumber: onRamps[managerChain.chain.chainSelector].getExpectedNextSequenceNumber(
          dstChainBnM1.chain.chainSelector
        ),
        nonce: managerChain.chain.nonceManager.outboundNonces(dstChainBnM1.chain.chainSelector, address(this))
      }),
      sender: abi.encode(address(this)),
      data: abi.encodePacked(),
      receiver: bob,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[dstChainBnM1.chain.chainSelector];

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(
      managerChain.chain.chainSelector, address(dstChainBnM1.token), address(offRamp), bob, 1e18
    );

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));

    assertEq(managerChain.stablecoin.balanceOf(alice), 0, "test_BridgeManagerToBnM1::1");
    assertEq(managerChain.stablecoin.balanceOf(bob), 0, "test_BridgeManagerToBnM1::2");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.governor)), 0, "test_BridgeManagerToBnM1::3");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 0, "test_BridgeManagerToBnM1::4");

    assertEq(dstChainBnM1.token.balanceOf(alice), 0, "test_BridgeManagerToBnM1::5");
    assertEq(dstChainBnM1.token.balanceOf(bob), 1e18, "test_BridgeManagerToBnM1::6");
    assertEq(dstChainBnM1.token.balanceOf(address(dstChainBnM1.tokenPool)), 0, "test_BridgeManagerToBnM1::7");
  }

  function test_BridgeBnM1ToManager() public {
    Client.EVMTokenAmount[] memory srcTokensAmounts = new Client.EVMTokenAmount[](1);
    srcTokensAmounts[0] = Client.EVMTokenAmount({token: address(dstChainBnM1.token), amount: 1e18});

    Client.EVM2AnyMessage memory srcMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(alice),
      data: abi.encodePacked(),
      tokenAmounts: srcTokensAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 300_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = dstChainBnM1.chain.router.getFee(managerChain.chain.chainSelector, srcMessage);

    vm.startPrank(admin);
    dstChainBnM1.token.grantRole(dstChainBnM1.token.MINTER_ROLE(), admin);
    dstChainBnM1.token.mint(bob, 1e18);
    vm.stopPrank();

    vm.startPrank(bob);
    dstChainBnM1.token.approve(address(dstChainBnM1.chain.router), 1e18);

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(
      managerChain.chain.chainSelector,
      address(dstChainBnM1.token),
      address(onRamps[dstChainBnM1.chain.chainSelector]),
      1e18
    );

    bytes32 srcId = dstChainBnM1.chain.router.ccipSend{value: fee}(managerChain.chain.chainSelector, srcMessage);
    vm.stopPrank();

    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(dstChainBnM1.tokenPool)),
      destTokenAddress: address(managerChain.stablecoin),
      destGasAmount: 300_000,
      extraData: abi.encodePacked(),
      amount: 1e18
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: srcId,
        sourceChainSelector: dstChainBnM1.chain.chainSelector,
        destChainSelector: managerChain.chain.chainSelector,
        sequenceNumber: onRamps[dstChainBnM1.chain.chainSelector].getExpectedNextSequenceNumber(
          managerChain.chain.chainSelector
        ),
        nonce: dstChainBnM1.chain.nonceManager.outboundNonces(managerChain.chain.chainSelector, address(this))
      }),
      sender: abi.encode(address(this)),
      data: abi.encodePacked(),
      receiver: alice,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[managerChain.chain.chainSelector];

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(
      dstChainBnM1.chain.chainSelector, address(managerChain.stablecoin), address(offRamp), alice, 1e18
    );

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));

    assertEq(dstChainBnM1.token.balanceOf(alice), 0, "test_BridgeBnM1ToManager::1");
    assertEq(dstChainBnM1.token.balanceOf(bob), 0, "test_BridgeBnM1ToManager::2");
    assertEq(dstChainBnM1.token.balanceOf(address(dstChainBnM1.tokenPool)), 0, "test_BridgeBnM1ToManager::3");

    assertEq(managerChain.stablecoin.balanceOf(alice), 1e18, "test_BridgeBnM1ToManager::4");
    assertEq(managerChain.stablecoin.balanceOf(bob), 0, "test_BridgeBnM1ToManager::5");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 0, "test_BridgeBnM1ToManager::6");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.governor)), 0, "test_BridgeBnM1ToManager::7");
  }

  function test_BridgeManagerToBnM2() public {
    Client.EVMTokenAmount[] memory srcTokensAmounts = new Client.EVMTokenAmount[](1);
    srcTokensAmounts[0] = Client.EVMTokenAmount({token: address(managerChain.stablecoin), amount: 1e18});

    Client.EVM2AnyMessage memory srcMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(bob),
      data: abi.encodePacked(),
      tokenAmounts: srcTokensAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 100_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = managerChain.chain.router.getFee(dstChainBnM2.chain.chainSelector, srcMessage);

    vm.startPrank(admin);
    managerChain.governor.grantRole(managerChain.governor.MINTER_ROLE(), admin);
    managerChain.governor.mint(alice, 1e18);
    vm.stopPrank();

    vm.startPrank(alice);
    managerChain.stablecoin.approve(address(managerChain.chain.router), 1e18);

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(
      dstChainBnM2.chain.chainSelector,
      address(managerChain.stablecoin),
      address(onRamps[managerChain.chain.chainSelector]),
      1e18
    );

    bytes32 srcId = managerChain.chain.router.ccipSend{value: fee}(dstChainBnM2.chain.chainSelector, srcMessage);
    vm.stopPrank();

    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(managerChain.tokenPool)),
      destTokenAddress: address(dstChainBnM2.token),
      destGasAmount: 100_000,
      extraData: abi.encodePacked(),
      amount: 1e18
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: srcId,
        sourceChainSelector: managerChain.chain.chainSelector,
        destChainSelector: dstChainBnM2.chain.chainSelector,
        sequenceNumber: onRamps[managerChain.chain.chainSelector].getExpectedNextSequenceNumber(
          dstChainBnM2.chain.chainSelector
        ),
        nonce: managerChain.chain.nonceManager.outboundNonces(dstChainBnM2.chain.chainSelector, address(this))
      }),
      sender: abi.encode(address(this)),
      data: abi.encodePacked(),
      receiver: bob,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[dstChainBnM2.chain.chainSelector];

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(
      managerChain.chain.chainSelector, address(dstChainBnM2.token), address(offRamp), bob, 1e18
    );

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));

    assertEq(managerChain.stablecoin.balanceOf(alice), 0, "test_BridgeManagerToBnM2::1");
    assertEq(managerChain.stablecoin.balanceOf(bob), 0, "test_BridgeManagerToBnM2::2");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.governor)), 0, "test_BridgeManagerToBnM2::3");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 0, "test_BridgeManagerToBnM2::4");

    assertEq(dstChainBnM2.token.balanceOf(alice), 0, "test_BridgeManagerToBnM2::5");
    assertEq(dstChainBnM2.token.balanceOf(bob), 1e18, "test_BridgeManagerToBnM2::6");
    assertEq(dstChainBnM2.token.balanceOf(address(dstChainBnM2.tokenPool)), 0, "test_BridgeManagerToBnM2::7");
  }

  function test_BridgeBnM2ToManager() public {
    Client.EVMTokenAmount[] memory srcTokensAmounts = new Client.EVMTokenAmount[](1);
    srcTokensAmounts[0] = Client.EVMTokenAmount({token: address(dstChainBnM2.token), amount: 1e18});

    Client.EVM2AnyMessage memory srcMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(alice),
      data: abi.encodePacked(),
      tokenAmounts: srcTokensAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 300_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = dstChainBnM2.chain.router.getFee(managerChain.chain.chainSelector, srcMessage);

    vm.startPrank(admin);
    dstChainBnM2.token.grantRole(dstChainBnM2.token.MINTER_ROLE(), admin);
    dstChainBnM2.token.mint(bob, 1e18);
    vm.stopPrank();

    vm.startPrank(bob);
    dstChainBnM2.token.approve(address(dstChainBnM2.chain.router), 1e18);

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(
      managerChain.chain.chainSelector,
      address(dstChainBnM2.token),
      address(onRamps[dstChainBnM2.chain.chainSelector]),
      1e18
    );

    bytes32 srcId = dstChainBnM2.chain.router.ccipSend{value: fee}(managerChain.chain.chainSelector, srcMessage);
    vm.stopPrank();

    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(dstChainBnM2.tokenPool)),
      destTokenAddress: address(managerChain.stablecoin),
      destGasAmount: 300_000,
      extraData: abi.encodePacked(),
      amount: 1e18
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: srcId,
        sourceChainSelector: dstChainBnM2.chain.chainSelector,
        destChainSelector: managerChain.chain.chainSelector,
        sequenceNumber: onRamps[dstChainBnM2.chain.chainSelector].getExpectedNextSequenceNumber(
          managerChain.chain.chainSelector
        ),
        nonce: dstChainBnM2.chain.nonceManager.outboundNonces(managerChain.chain.chainSelector, address(this))
      }),
      sender: abi.encode(address(this)),
      data: abi.encodePacked(),
      receiver: alice,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[managerChain.chain.chainSelector];

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(
      dstChainBnM2.chain.chainSelector, address(managerChain.stablecoin), address(offRamp), alice, 1e18
    );

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));

    assertEq(dstChainBnM2.token.balanceOf(alice), 0, "test_BridgeBnM2ToManager::1");
    assertEq(dstChainBnM2.token.balanceOf(bob), 0, "test_BridgeBnM2ToManager::2");
    assertEq(dstChainBnM2.token.balanceOf(address(dstChainBnM2.tokenPool)), 0, "test_BridgeBnM2ToManager::3");

    assertEq(managerChain.stablecoin.balanceOf(alice), 1e18, "test_BridgeBnM2ToManager::4");
    assertEq(managerChain.stablecoin.balanceOf(bob), 0, "test_BridgeBnM2ToManager::5");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 0, "test_BridgeBnM2ToManager::6");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.governor)), 0, "test_BridgeBnM2ToManager::7");
  }

  function test_BridgeManagerToLnR1() public {
    Client.EVMTokenAmount[] memory srcTokensAmounts = new Client.EVMTokenAmount[](1);
    srcTokensAmounts[0] = Client.EVMTokenAmount({token: address(managerChain.stablecoin), amount: 1e18});

    Client.EVM2AnyMessage memory srcMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(bob),
      data: abi.encodePacked(),
      tokenAmounts: srcTokensAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 100_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = managerChain.chain.router.getFee(dstChainLnR1.chain.chainSelector, srcMessage);

    vm.startPrank(admin);
    managerChain.governor.grantRole(managerChain.governor.MINTER_ROLE(), admin);
    managerChain.governor.mint(alice, 1e18);
    vm.stopPrank();

    vm.startPrank(alice);
    managerChain.stablecoin.approve(address(managerChain.chain.router), 1e18);

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(
      dstChainLnR1.chain.chainSelector,
      address(managerChain.stablecoin),
      address(onRamps[managerChain.chain.chainSelector]),
      1e18
    );

    bytes32 srcId = managerChain.chain.router.ccipSend{value: fee}(dstChainLnR1.chain.chainSelector, srcMessage);
    vm.stopPrank();

    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(managerChain.tokenPool)),
      destTokenAddress: address(dstChainLnR1.token),
      destGasAmount: 100_000,
      extraData: abi.encodePacked(),
      amount: 1e18
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: srcId,
        sourceChainSelector: managerChain.chain.chainSelector,
        destChainSelector: dstChainLnR1.chain.chainSelector,
        sequenceNumber: onRamps[managerChain.chain.chainSelector].getExpectedNextSequenceNumber(
          dstChainLnR1.chain.chainSelector
        ),
        nonce: managerChain.chain.nonceManager.outboundNonces(dstChainLnR1.chain.chainSelector, address(this))
      }),
      sender: abi.encode(address(this)),
      data: abi.encodePacked(),
      receiver: bob,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[dstChainLnR1.chain.chainSelector];

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(
      managerChain.chain.chainSelector, address(dstChainLnR1.token), address(offRamp), bob, 1e18
    );

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));

    assertEq(managerChain.stablecoin.balanceOf(alice), 0, "test_BridgeManagerToLnR1::1");
    assertEq(managerChain.stablecoin.balanceOf(bob), 0, "test_BridgeManagerToLnR1::2");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.governor)), 0, "test_BridgeManagerToLnR1::3");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 1e18, "test_BridgeManagerToLnR1::4");

    assertEq(dstChainLnR1.token.balanceOf(alice), 0, "test_BridgeManagerToLnR1::5");
    assertEq(dstChainLnR1.token.balanceOf(bob), 1e18, "test_BridgeManagerToLnR1::6");
    assertEq(dstChainLnR1.token.balanceOf(address(dstChainLnR1.tokenPool)), 0, "test_BridgeManagerToLnR1::7");
  }

  function test_BridgeLnR1ToManager() public {
    Client.EVMTokenAmount[] memory srcTokensAmounts = new Client.EVMTokenAmount[](1);
    srcTokensAmounts[0] = Client.EVMTokenAmount({token: address(dstChainLnR1.token), amount: 1e18});

    Client.EVM2AnyMessage memory srcMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(alice),
      data: abi.encodePacked(),
      tokenAmounts: srcTokensAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 100_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = dstChainLnR1.chain.router.getFee(managerChain.chain.chainSelector, srcMessage);

    vm.startPrank(admin);
    dstChainLnR1.token.grantRole(dstChainLnR1.token.MINTER_ROLE(), admin);
    dstChainLnR1.token.mint(bob, 1e18);
    vm.stopPrank();

    vm.startPrank(bob);
    dstChainLnR1.token.approve(address(dstChainLnR1.chain.router), 1e18);

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(
      managerChain.chain.chainSelector,
      address(dstChainLnR1.token),
      address(onRamps[dstChainLnR1.chain.chainSelector]),
      1e18
    );

    bytes32 srcId = dstChainLnR1.chain.router.ccipSend{value: fee}(managerChain.chain.chainSelector, srcMessage);
    vm.stopPrank();

    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(dstChainLnR1.tokenPool)),
      destTokenAddress: address(managerChain.stablecoin),
      destGasAmount: 100_000,
      extraData: abi.encodePacked(),
      amount: 1e18
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: srcId,
        sourceChainSelector: dstChainLnR1.chain.chainSelector,
        destChainSelector: managerChain.chain.chainSelector,
        sequenceNumber: onRamps[dstChainLnR1.chain.chainSelector].getExpectedNextSequenceNumber(
          managerChain.chain.chainSelector
        ),
        nonce: dstChainLnR1.chain.nonceManager.outboundNonces(managerChain.chain.chainSelector, address(this))
      }),
      sender: abi.encode(address(this)),
      data: abi.encodePacked(),
      receiver: alice,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[managerChain.chain.chainSelector];

    vm.startPrank(admin);
    managerChain.governor.grantRole(managerChain.governor.MINTER_ROLE(), admin);
    managerChain.governor.mint(admin, 50e18);

    managerChain.stablecoin.approve(address(managerChain.tokenPool), 50e18);
    managerChain.tokenPool.provideLiquidity(50e18);
    vm.stopPrank();

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(
      dstChainLnR1.chain.chainSelector, address(managerChain.stablecoin), address(offRamp), alice, 1e18
    );

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));

    assertEq(dstChainLnR1.token.balanceOf(alice), 0, "test_BridgeLnR1ToManager::1");
    assertEq(dstChainLnR1.token.balanceOf(bob), 0, "test_BridgeLnR1ToManager::2");
    assertEq(dstChainLnR1.token.balanceOf(address(dstChainLnR1.tokenPool)), 0, "test_BridgeLnR1ToManager::3");

    assertEq(managerChain.stablecoin.balanceOf(alice), 1e18, "test_BridgeLnR1ToManager::4");
    assertEq(managerChain.stablecoin.balanceOf(bob), 0, "test_BridgeLnR1ToManager::5");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 49e18, "test_BridgeLnR1ToManager::6");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.governor)), 0, "test_BridgeLnR1ToManager::7");
  }

  function test_BridgeManagerToLnR2() public {
    Client.EVMTokenAmount[] memory srcTokensAmounts = new Client.EVMTokenAmount[](1);
    srcTokensAmounts[0] = Client.EVMTokenAmount({token: address(managerChain.stablecoin), amount: 1e18});

    Client.EVM2AnyMessage memory srcMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(bob),
      data: abi.encodePacked(),
      tokenAmounts: srcTokensAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 100_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = managerChain.chain.router.getFee(dstChainLnR2.chain.chainSelector, srcMessage);

    vm.startPrank(admin);
    managerChain.governor.grantRole(managerChain.governor.MINTER_ROLE(), admin);
    managerChain.governor.mint(alice, 1e18);
    vm.stopPrank();

    vm.startPrank(alice);
    managerChain.stablecoin.approve(address(managerChain.chain.router), 1e18);

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(
      dstChainLnR2.chain.chainSelector,
      address(managerChain.stablecoin),
      address(onRamps[managerChain.chain.chainSelector]),
      1e18
    );

    bytes32 srcId = managerChain.chain.router.ccipSend{value: fee}(dstChainLnR2.chain.chainSelector, srcMessage);
    vm.stopPrank();

    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(managerChain.tokenPool)),
      destTokenAddress: address(dstChainLnR2.token),
      destGasAmount: 100_000,
      extraData: abi.encodePacked(),
      amount: 1e18
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: srcId,
        sourceChainSelector: managerChain.chain.chainSelector,
        destChainSelector: dstChainLnR2.chain.chainSelector,
        sequenceNumber: onRamps[managerChain.chain.chainSelector].getExpectedNextSequenceNumber(
          dstChainLnR2.chain.chainSelector
        ),
        nonce: managerChain.chain.nonceManager.outboundNonces(dstChainLnR2.chain.chainSelector, address(this))
      }),
      sender: abi.encode(address(this)),
      data: abi.encodePacked(),
      receiver: bob,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[dstChainLnR2.chain.chainSelector];

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(
      managerChain.chain.chainSelector, address(dstChainLnR2.token), address(offRamp), bob, 1e18
    );

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));

    assertEq(managerChain.stablecoin.balanceOf(alice), 0, "test_BridgeManagerToLnR2::1");
    assertEq(managerChain.stablecoin.balanceOf(bob), 0, "test_BridgeManagerToLnR2::2");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.governor)), 0, "test_BridgeManagerToLnR2::3");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 1e18, "test_BridgeManagerToLnR2::4");

    assertEq(dstChainLnR2.token.balanceOf(alice), 0, "test_BridgeManagerToLnR2::5");
    assertEq(dstChainLnR2.token.balanceOf(bob), 1e18, "test_BridgeManagerToLnR2::6");
    assertEq(dstChainLnR2.token.balanceOf(address(dstChainLnR2.tokenPool)), 0, "test_BridgeManagerToLnR2::7");
  }

  function test_BridgeLnR2ToManager() public {
    Client.EVMTokenAmount[] memory srcTokensAmounts = new Client.EVMTokenAmount[](1);
    srcTokensAmounts[0] = Client.EVMTokenAmount({token: address(dstChainLnR2.token), amount: 1e18});

    Client.EVM2AnyMessage memory srcMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(alice),
      data: abi.encodePacked(),
      tokenAmounts: srcTokensAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 300_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = dstChainLnR2.chain.router.getFee(managerChain.chain.chainSelector, srcMessage);

    vm.startPrank(admin);
    dstChainLnR2.token.grantRole(dstChainLnR2.token.MINTER_ROLE(), admin);
    dstChainLnR2.token.mint(bob, 1e18);
    vm.stopPrank();

    vm.startPrank(bob);
    dstChainLnR2.token.approve(address(dstChainLnR2.chain.router), 1e18);

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(
      managerChain.chain.chainSelector,
      address(dstChainLnR2.token),
      address(onRamps[dstChainLnR2.chain.chainSelector]),
      1e18
    );

    bytes32 srcId = dstChainLnR2.chain.router.ccipSend{value: fee}(managerChain.chain.chainSelector, srcMessage);
    vm.stopPrank();

    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(dstChainLnR2.tokenPool)),
      destTokenAddress: address(managerChain.stablecoin),
      destGasAmount: 300_000,
      extraData: abi.encodePacked(),
      amount: 1e18
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: srcId,
        sourceChainSelector: dstChainLnR2.chain.chainSelector,
        destChainSelector: managerChain.chain.chainSelector,
        sequenceNumber: onRamps[dstChainLnR2.chain.chainSelector].getExpectedNextSequenceNumber(
          managerChain.chain.chainSelector
        ),
        nonce: dstChainLnR2.chain.nonceManager.outboundNonces(managerChain.chain.chainSelector, address(this))
      }),
      sender: abi.encode(address(this)),
      data: abi.encodePacked(),
      receiver: alice,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[managerChain.chain.chainSelector];

    vm.startPrank(admin);
    managerChain.governor.grantRole(managerChain.governor.MINTER_ROLE(), admin);
    managerChain.governor.mint(admin, 50e18);

    managerChain.stablecoin.approve(address(managerChain.tokenPool), 50e18);
    managerChain.tokenPool.provideLiquidity(50e18);
    vm.stopPrank();

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(
      dstChainLnR2.chain.chainSelector, address(managerChain.stablecoin), address(offRamp), alice, 1e18
    );

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));

    assertEq(dstChainLnR2.token.balanceOf(alice), 0, "test_BridgeLnR2ToManager::1");
    assertEq(dstChainLnR2.token.balanceOf(bob), 0, "test_BridgeLnR2ToManager::2");
    assertEq(dstChainLnR2.token.balanceOf(address(dstChainLnR2.tokenPool)), 0, "test_BridgeLnR2ToManager::3");

    assertEq(managerChain.stablecoin.balanceOf(alice), 1e18, "test_BridgeLnR2ToManager::4");
    assertEq(managerChain.stablecoin.balanceOf(bob), 0, "test_BridgeLnR2ToManager::5");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 49e18, "test_BridgeLnR2ToManager::6");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.governor)), 0, "test_BridgeLnR2ToManager::7");
  }

  function test_UpdateGroups() public {
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainLnR1.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE),
      "test_UpdateGroups::1"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainLnR2.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE),
      "test_UpdateGroups::2"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainBnM1.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT),
      "test_UpdateGroups::3"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainBnM2.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT),
      "test_UpdateGroups::4"
    );

    uint256 supplyLnR1 = 30e18;
    uint256 supplyLnR2 = 20e18;
    uint256 supplyBnM1 = 10e18;
    uint256 supplyBnM2 = 5e18;

    vm.startPrank(admin);
    managerChain.governor.grantRole(managerChain.governor.MINTER_ROLE(), admin);
    managerChain.governor.mint(address(managerChain.tokenPool), supplyLnR1 + supplyLnR2);

    assertEq(managerChain.tokenPool.getLockedTokens(), supplyLnR1 + supplyLnR2, "test_UpdateGroups::5");

    // Update LnR1 to BURN_AND_MINT and BnM2 to LOCK_AND_RELEASE
    HybridTokenPoolAbstract.GroupUpdate[] memory updates = new HybridTokenPoolAbstract.GroupUpdate[](2);

    updates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR1.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: supplyLnR1
    });
    updates[1] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainBnM2.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE,
      remoteChainSupply: supplyBnM2
    });

    // Events are emitted in the order they're processed in the loop
    // First update: LnR1 to BURN_AND_MINT
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityMigrated(
      dstChainLnR1.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT, supplyLnR1
    );
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(
      dstChainLnR1.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT
    );
    // Second update: BnM2 to LOCK_AND_RELEASE
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityMigrated(
      dstChainBnM2.chain.chainSelector, HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE, supplyBnM2
    );
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(
      dstChainBnM2.chain.chainSelector, HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE
    );

    managerChain.tokenPool.updateGroups(updates);

    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainLnR1.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT),
      "test_UpdateGroups::6"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainLnR2.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE),
      "test_UpdateGroups::7"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainBnM1.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT),
      "test_UpdateGroups::8"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainBnM2.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE),
      "test_UpdateGroups::9"
    );
    assertEq(
      managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)),
      supplyLnR2 + supplyBnM2,
      "test_UpdateGroups::10"
    );
    assertEq(managerChain.tokenPool.getLockedTokens(), supplyLnR2 + supplyBnM2, "test_UpdateGroups::11");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.governor)), 0, "test_UpdateGroups::12");

    // Update LnR2 to BURN_AND_MINT and BnM1 to LOCK_AND_RELEASE
    updates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR2.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: supplyLnR2
    });
    updates[1] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainBnM1.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE,
      remoteChainSupply: supplyBnM1
    });
    // First update: LnR2 to BURN_AND_MINT
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityMigrated(
      dstChainLnR2.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT, supplyLnR2
    );
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(
      dstChainLnR2.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT
    );
    // Second update: BnM1 to LOCK_AND_RELEASE
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityMigrated(
      dstChainBnM1.chain.chainSelector, HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE, supplyBnM1
    );
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(
      dstChainBnM1.chain.chainSelector, HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE
    );

    managerChain.tokenPool.updateGroups(updates);

    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainLnR1.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT),
      "test_UpdateGroups::13"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainLnR2.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT),
      "test_UpdateGroups::14"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainBnM1.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE),
      "test_UpdateGroups::15"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainBnM2.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE),
      "test_UpdateGroups::16"
    );
    assertEq(
      managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)),
      supplyBnM1 + supplyBnM2,
      "test_UpdateGroups::17"
    );
    assertEq(managerChain.tokenPool.getLockedTokens(), supplyBnM1 + supplyBnM2, "test_UpdateGroups::18");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.governor)), 0, "test_UpdateGroups::19");

    // Update LnR1 and LnR2 to LOCK_AND_RELEASE and BnM1 and BnM2 to BURN_AND_MINT, with no liquidity
    // migration for LnR1 and BnM2
    updates = new HybridTokenPoolAbstract.GroupUpdate[](4);
    updates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR1.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE,
      remoteChainSupply: 0
    });
    updates[1] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR2.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE,
      remoteChainSupply: supplyLnR2
    });
    updates[2] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainBnM1.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: supplyBnM1
    });
    updates[3] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainBnM2.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: 0
    });
    // First update: LnR1 to LOCK_AND_RELEASE (no liquidity migration)
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(
      dstChainLnR1.chain.chainSelector, HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE
    );
    // Second update: LnR2 to LOCK_AND_RELEASE
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityMigrated(
      dstChainLnR2.chain.chainSelector, HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE, supplyLnR2
    );
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(
      dstChainLnR2.chain.chainSelector, HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE
    );
    // Third update: BnM1 to BURN_AND_MINT
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityMigrated(
      dstChainBnM1.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT, supplyBnM1
    );
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(
      dstChainBnM1.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT
    );
    // Fourth update: BnM2 to BURN_AND_MINT (no liquidity migration)
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(
      dstChainBnM2.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT
    );

    managerChain.tokenPool.updateGroups(updates);

    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainLnR1.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE),
      "test_UpdateGroups::20"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainLnR2.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE),
      "test_UpdateGroups::21"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainBnM1.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT),
      "test_UpdateGroups::22"
    );
    assertEq(
      uint8(managerChain.tokenPool.getGroup(dstChainBnM2.chain.chainSelector)),
      uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT),
      "test_UpdateGroups::23"
    );
    assertEq(
      managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)),
      supplyBnM2 + supplyLnR2,
      "test_UpdateGroups::24"
    );
    assertEq(managerChain.tokenPool.getLockedTokens(), supplyBnM2 + supplyLnR2, "test_UpdateGroups::25");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.governor)), 0, "test_UpdateGroups::26");

    vm.stopPrank();
  }

  function test_Revert_UpdateGroups() public {
    vm.startPrank(admin);

    HybridTokenPoolAbstract.GroupUpdate[] memory updates = new HybridTokenPoolAbstract.GroupUpdate[](1);

    // Revert on same group
    updates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR1.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE,
      remoteChainSupply: 0
    });
    vm.expectRevert(
      abi.encodeWithSelector(
        HybridTokenPoolAbstract.InvalidGroupUpdate.selector,
        dstChainLnR1.chain.chainSelector,
        uint8(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE)
      )
    );
    managerChain.tokenPool.updateGroups(updates);

    updates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR2.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE,
      remoteChainSupply: 0
    });
    vm.expectRevert(
      abi.encodeWithSelector(
        HybridTokenPoolAbstract.InvalidGroupUpdate.selector,
        dstChainLnR2.chain.chainSelector,
        uint8(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE)
      )
    );
    managerChain.tokenPool.updateGroups(updates);

    updates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainBnM1.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: 0
    });
    vm.expectRevert(
      abi.encodeWithSelector(
        HybridTokenPoolAbstract.InvalidGroupUpdate.selector,
        dstChainBnM1.chain.chainSelector,
        uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT)
      )
    );
    managerChain.tokenPool.updateGroups(updates);

    updates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainBnM2.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: 0
    });
    vm.expectRevert(
      abi.encodeWithSelector(
        HybridTokenPoolAbstract.InvalidGroupUpdate.selector,
        dstChainBnM2.chain.chainSelector,
        uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT)
      )
    );
    managerChain.tokenPool.updateGroups(updates);

    // Revert on non supported chains
    updates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: _chainCounter + 1,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: 0
    });
    vm.expectRevert(
      abi.encodeWithSelector(
        HybridTokenPoolAbstract.InvalidGroupUpdate.selector,
        _chainCounter + 1,
        uint8(HybridTokenPoolAbstract.Group.BURN_AND_MINT)
      )
    );
    managerChain.tokenPool.updateGroups(updates);

    vm.stopPrank();
  }

  function test_SetRebalancer() public {
    vm.startPrank(admin);

    assertEq(managerChain.tokenPool.getRebalancer(), admin, "test_SetRebalancer::1");

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.RebalancerSet(admin, alice);
    managerChain.tokenPool.setRebalancer(alice);

    assertEq(managerChain.tokenPool.getRebalancer(), alice, "test_SetRebalancer::2");

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.RebalancerSet(alice, admin);
    managerChain.tokenPool.setRebalancer(admin);

    assertEq(managerChain.tokenPool.getRebalancer(), admin, "test_SetRebalancer::3");

    vm.stopPrank();
  }

  function test_ProvideLiquidity() public {
    vm.startPrank(admin);
    managerChain.governor.grantRole(managerChain.governor.MINTER_ROLE(), admin);
    managerChain.governor.mint(address(admin), 1e18);
    managerChain.stablecoin.approve(address(managerChain.tokenPool), 1e18);

    assertEq(managerChain.stablecoin.balanceOf(admin), 1e18, "test_ProvideLiquidity::1");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 0, "test_ProvideLiquidity::2");
    assertEq(managerChain.tokenPool.getLockedTokens(), 0, "test_ProvideLiquidity::3");

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityAdded(admin, 1e18);

    managerChain.tokenPool.provideLiquidity(1e18);

    assertEq(managerChain.stablecoin.balanceOf(admin), 0, "test_ProvideLiquidity::4");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 1e18, "test_ProvideLiquidity::5");
    assertEq(managerChain.tokenPool.getLockedTokens(), 1e18, "test_ProvideLiquidity::6");

    vm.stopPrank();

    vm.expectRevert(HybridTokenPoolAbstract.LiquidityAmountCannotBeZero.selector);
    managerChain.tokenPool.provideLiquidity(0);

    vm.expectRevert(abi.encodeWithSelector(TokenPool.Unauthorized.selector, address(this)));
    managerChain.tokenPool.provideLiquidity(1);
  }

  function test_withdrawLiquidity() public {
    vm.startPrank(admin);
    managerChain.governor.grantRole(managerChain.governor.MINTER_ROLE(), admin);
    managerChain.governor.mint(address(admin), 1e18);
    managerChain.stablecoin.approve(address(managerChain.tokenPool), 1e18);

    assertEq(managerChain.stablecoin.balanceOf(admin), 1e18, "test_withdrawLiquidity::1");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 0, "test_withdrawLiquidity::2");
    assertEq(managerChain.tokenPool.getLockedTokens(), 0, "test_withdrawLiquidity::3");

    managerChain.tokenPool.provideLiquidity(1e18);

    assertEq(managerChain.stablecoin.balanceOf(admin), 0, "test_withdrawLiquidity::4");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 1e18, "test_withdrawLiquidity::5");
    assertEq(managerChain.tokenPool.getLockedTokens(), 1e18, "test_withdrawLiquidity::6");

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityRemoved(admin, 0.5e18);

    managerChain.tokenPool.withdrawLiquidity(0.5e18);

    assertEq(managerChain.stablecoin.balanceOf(admin), 0.5e18, "test_withdrawLiquidity::7");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 0.5e18, "test_withdrawLiquidity::8");
    assertEq(managerChain.tokenPool.getLockedTokens(), 0.5e18, "test_withdrawLiquidity::9");

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityRemoved(admin, 0.5e18);

    managerChain.tokenPool.withdrawLiquidity(0.5e18);

    assertEq(managerChain.stablecoin.balanceOf(admin), 1e18, "test_withdrawLiquidity::10");
    assertEq(managerChain.stablecoin.balanceOf(address(managerChain.tokenPool)), 0, "test_withdrawLiquidity::11");
    assertEq(managerChain.tokenPool.getLockedTokens(), 0, "test_withdrawLiquidity::12");

    vm.stopPrank();

    vm.expectRevert(HybridTokenPoolAbstract.LiquidityAmountCannotBeZero.selector);
    managerChain.tokenPool.withdrawLiquidity(0);

    vm.expectRevert(abi.encodeWithSelector(TokenPool.Unauthorized.selector, address(this)));
    managerChain.tokenPool.withdrawLiquidity(1);
  }
}
