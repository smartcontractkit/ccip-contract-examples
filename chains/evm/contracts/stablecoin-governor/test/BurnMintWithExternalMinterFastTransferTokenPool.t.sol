// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {BurnMintExternalMinterTokenPoolAbstract} from "../BurnMintExternalMinterTokenPoolAbstract.sol";
import "../BurnMintWithExternalMinterFastTransferTokenPool.sol";
import {TokenGovernor} from "../TokenGovernor.sol";
import "./Utils.t.sol";
import {Stablecoin} from "./utils/Stablecoin.sol";
import {Router} from "@chainlink/contracts-ccip/contracts/Router.sol";
import {IFastTransferPool} from "@chainlink/contracts-ccip/contracts/interfaces/IFastTransferPool.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";
import {BurnMintTokenPool} from "@chainlink/contracts-ccip/contracts/pools/BurnMintTokenPool.sol";
import {BurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/BurnMintERC20.sol";

contract BurnMintWithExternalMinterFastTransferTokenPoolTest is Utils {
  struct TestChain {
    CCIPChain chain;
    BurnMintWithExternalMinterFastTransferTokenPool tokenPool;
    TokenGovernor governor;
    Stablecoin stablecoin;
  }

  struct DstChain {
    CCIPChain chain;
    BurnMintTokenPool tokenPool;
    BurnMintERC20 token;
  }

  TestChain srcChain;
  DstChain dstChain;

  function setUp() public {
    _addChains(2);
    _wireAll();

    srcChain.chain = chains[0];
    dstChain.chain = chains[1];

    vm.startPrank(admin);

    // Setup source chain with fast transfer pool
    {
      srcChain.stablecoin = new Stablecoin();
      srcChain.governor = new TokenGovernor(address(srcChain.stablecoin), 0, admin);

      srcChain.tokenPool = new BurnMintWithExternalMinterFastTransferTokenPool(
        address(srcChain.governor),
        IERC20(address(srcChain.stablecoin)),
        18,
        new address[](0),
        address(srcChain.chain.armProxy),
        address(srcChain.chain.router)
      );

      srcChain.stablecoin.initialize("Stablecoin", "STABLE");
      srcChain.stablecoin.transferOwnership(address(srcChain.governor));
      srcChain.governor.acceptOwnership();

      srcChain.governor.grantRole(srcChain.governor.BRIDGE_MINTER_OR_BURNER_ROLE(), address(srcChain.tokenPool));

      srcChain.chain.tokenAdminRegistry.proposeAdministrator(address(srcChain.stablecoin), admin);
      srcChain.chain.tokenAdminRegistry.acceptAdminRole(address(srcChain.stablecoin));
      srcChain.chain.tokenAdminRegistry.setPool(address(srcChain.stablecoin), address(srcChain.tokenPool));
    }

    // Setup destination chain with regular burn/mint pool
    {
      dstChain.token = new BurnMintERC20("Stablecoin", "STABLE", 18, type(uint256).max, 0);
      dstChain.tokenPool = new BurnMintTokenPool(
        dstChain.token, 18, new address[](0), address(dstChain.chain.armProxy), address(dstChain.chain.router)
      );

      dstChain.token.grantMintAndBurnRoles(address(dstChain.tokenPool));

      dstChain.chain.tokenAdminRegistry.proposeAdministrator(address(dstChain.token), admin);
      dstChain.chain.tokenAdminRegistry.acceptAdminRole(address(dstChain.token));
      dstChain.chain.tokenAdminRegistry.setPool(address(dstChain.token), address(dstChain.tokenPool));
    }

    {
      FastTransferTokenPoolAbstract.DestChainConfigUpdateArgs[] memory destChainConfigArgs =
        new FastTransferTokenPoolAbstract.DestChainConfigUpdateArgs[](1);
      destChainConfigArgs[0] = FastTransferTokenPoolAbstract.DestChainConfigUpdateArgs({
        fillerAllowlistEnabled: false,
        fastTransferFillerFeeBps: 100,
        fastTransferPoolFeeBps: 0,
        settlementOverheadGas: 300_000,
        remoteChainSelector: dstChain.chain.chainSelector,
        chainFamilySelector: Internal.CHAIN_FAMILY_SELECTOR_EVM,
        maxFillAmountPerRequest: 100 ether,
        destinationPool: abi.encode(address(dstChain.tokenPool)),
        customExtraArgs: ""
      });
      srcChain.tokenPool.updateDestChainConfig(destChainConfigArgs);
    }

    vm.stopPrank();

    // Link the pools
    _linkTokenPools(
      srcChain.chain.chainSelector,
      address(srcChain.tokenPool),
      dstChain.chain.chainSelector,
      address(dstChain.tokenPool)
    );

    vm.label(address(srcChain.stablecoin), "STABLE_SRC");
    vm.label(address(srcChain.tokenPool), "FastTransferTokenPool_SRC");
    vm.label(address(srcChain.governor), "TokenGovernor_SRC");

    vm.label(address(dstChain.token), "STABLE_DST");
    vm.label(address(dstChain.tokenPool), "TokenPool_DST");

    vm.deal(alice, 1e18);
    vm.deal(bob, 1e18);
  }

  function test_constructor() public view {
    assertEq(
      srcChain.tokenPool.typeAndVersion(),
      "BurnMintWithExternalMinterFastTransferTokenPool 1.6.0",
      "test_Constructor::1"
    );
    assertEq(srcChain.tokenPool.getMinter(), address(srcChain.governor), "test_Constructor::2");
    assertEq(address(srcChain.tokenPool.getToken()), address(srcChain.stablecoin), "test_Constructor::3");
    assertEq(srcChain.tokenPool.getTokenDecimals(), 18, "test_Constructor::4");
    assertEq(srcChain.tokenPool.getRmnProxy(), address(srcChain.chain.armProxy), "test_Constructor::5");
    assertEq(srcChain.tokenPool.getRouter(), address(srcChain.chain.router), "test_Constructor::6");
  }

  function test_constructor_RevertWhen_TokenMismatch() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        BurnMintExternalMinterTokenPoolAbstract.TokenMismatch.selector,
        IERC20(address(dstChain.token)),
        IERC20(address(srcChain.stablecoin))
      )
    );
    new BurnMintWithExternalMinterFastTransferTokenPool(
      address(srcChain.governor),
      IERC20(address(dstChain.token)),
      18,
      new address[](0),
      address(srcChain.chain.armProxy),
      address(srcChain.chain.router)
    );
  }

  function test_BridgeSourceToDestination() public {
    Client.EVMTokenAmount[] memory srcTokensAmounts = new Client.EVMTokenAmount[](1);
    srcTokensAmounts[0] = Client.EVMTokenAmount({token: address(srcChain.stablecoin), amount: 1e18});

    Client.EVM2AnyMessage memory srcMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(bob),
      data: abi.encodePacked(),
      tokenAmounts: srcTokensAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 100_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = srcChain.chain.router.getFee(dstChain.chain.chainSelector, srcMessage);

    // Setup: Mint tokens to alice
    vm.startPrank(admin);
    srcChain.governor.grantRole(srcChain.governor.MINTER_ROLE(), admin);
    srcChain.governor.mint(alice, 1e18);
    vm.stopPrank();

    vm.startPrank(alice);
    srcChain.stablecoin.approve(address(srcChain.chain.router), 1e18);

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(
      dstChain.chain.chainSelector, address(srcChain.stablecoin), address(onRamps[srcChain.chain.chainSelector]), 1e18
    );

    bytes32 srcId = srcChain.chain.router.ccipSend{value: fee}(dstChain.chain.chainSelector, srcMessage);
    vm.stopPrank();

    // Execute on destination
    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(srcChain.tokenPool)),
      destTokenAddress: address(dstChain.token),
      destGasAmount: 100_000,
      extraData: abi.encodePacked(),
      amount: 1e18
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: srcId,
        sourceChainSelector: srcChain.chain.chainSelector,
        destChainSelector: dstChain.chain.chainSelector,
        sequenceNumber: onRamps[srcChain.chain.chainSelector].getExpectedNextSequenceNumber(dstChain.chain.chainSelector),
        nonce: srcChain.chain.nonceManager.outboundNonces(dstChain.chain.chainSelector, address(this))
      }),
      sender: abi.encode(address(this)),
      data: abi.encodePacked(),
      receiver: bob,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[dstChain.chain.chainSelector];

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(srcChain.chain.chainSelector, address(dstChain.token), address(offRamp), bob, 1e18);

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));

    // Verify balances
    assertEq(srcChain.stablecoin.balanceOf(alice), 0, "test_BridgeSourceToDestination::1");
    assertEq(srcChain.stablecoin.balanceOf(bob), 0, "test_BridgeSourceToDestination::2");
    assertEq(srcChain.stablecoin.balanceOf(address(srcChain.governor)), 0, "test_BridgeSourceToDestination::3");
    assertEq(srcChain.stablecoin.balanceOf(address(srcChain.tokenPool)), 0, "test_BridgeSourceToDestination::4");

    assertEq(dstChain.token.balanceOf(alice), 0, "test_BridgeSourceToDestination::5");
    assertEq(dstChain.token.balanceOf(bob), 1e18, "test_BridgeSourceToDestination::6");
    assertEq(dstChain.token.balanceOf(address(dstChain.tokenPool)), 0, "test_BridgeSourceToDestination::7");
  }

  function test_BridgeDestinationToSource() public {
    Client.EVMTokenAmount[] memory srcTokensAmounts = new Client.EVMTokenAmount[](1);
    srcTokensAmounts[0] = Client.EVMTokenAmount({token: address(dstChain.token), amount: 1e18});

    Client.EVM2AnyMessage memory srcMessage = Client.EVM2AnyMessage({
      receiver: abi.encode(alice),
      data: abi.encodePacked(),
      tokenAmounts: srcTokensAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 300_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = dstChain.chain.router.getFee(srcChain.chain.chainSelector, srcMessage);

    // Setup: Mint tokens to bob on destination
    vm.startPrank(admin);
    dstChain.token.grantRole(dstChain.token.MINTER_ROLE(), admin);
    dstChain.token.mint(bob, 1e18);
    vm.stopPrank();

    vm.startPrank(bob);
    dstChain.token.approve(address(dstChain.chain.router), 1e18);

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(
      srcChain.chain.chainSelector, address(dstChain.token), address(onRamps[dstChain.chain.chainSelector]), 1e18
    );

    bytes32 srcId = dstChain.chain.router.ccipSend{value: fee}(srcChain.chain.chainSelector, srcMessage);
    vm.stopPrank();

    // Execute on source
    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(dstChain.tokenPool)),
      destTokenAddress: address(srcChain.stablecoin),
      destGasAmount: 300_000,
      extraData: abi.encodePacked(),
      amount: 1e18
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: srcId,
        sourceChainSelector: dstChain.chain.chainSelector,
        destChainSelector: srcChain.chain.chainSelector,
        sequenceNumber: onRamps[dstChain.chain.chainSelector].getExpectedNextSequenceNumber(srcChain.chain.chainSelector),
        nonce: dstChain.chain.nonceManager.outboundNonces(srcChain.chain.chainSelector, address(this))
      }),
      sender: abi.encode(address(this)),
      data: abi.encodePacked(),
      receiver: alice,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[srcChain.chain.chainSelector];

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(
      dstChain.chain.chainSelector, address(srcChain.stablecoin), address(offRamp), alice, 1e18
    );

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));

    // Verify balances
    assertEq(dstChain.token.balanceOf(alice), 0, "test_BridgeDestinationToSource::1");
    assertEq(dstChain.token.balanceOf(bob), 0, "test_BridgeDestinationToSource::2");
    assertEq(dstChain.token.balanceOf(address(dstChain.tokenPool)), 0, "test_BridgeDestinationToSource::3");

    assertEq(srcChain.stablecoin.balanceOf(alice), 1e18, "test_BridgeDestinationToSource::4");
    assertEq(srcChain.stablecoin.balanceOf(bob), 0, "test_BridgeDestinationToSource::5");
    assertEq(srcChain.stablecoin.balanceOf(address(srcChain.tokenPool)), 0, "test_BridgeDestinationToSource::6");
    assertEq(srcChain.stablecoin.balanceOf(address(srcChain.governor)), 0, "test_BridgeDestinationToSource::7");
  }

  function test_CcipSendToken() public {
    bytes32 mockMessageId = keccak256("mockMessageId");
    uint256 adminBalanceBefore = srcChain.stablecoin.balanceOf(admin);
    uint256 sourceAmount = 1e18;
    deal(address(srcChain.stablecoin), alice, sourceAmount);
    uint256 aliceBalanceBefore = srcChain.stablecoin.balanceOf(alice);
    IFastTransferPool.Quote memory quote = srcChain.tokenPool.getCcipSendTokenFee(
      dstChain.chain.chainSelector, sourceAmount, abi.encode(alice), address(0), ""
    );

    uint256 expectedFastFee = (sourceAmount * 100) / 10_000;
    assertEq(quote.fastTransferFee, expectedFastFee, "test_CcipSendToken::1");
    vm.mockCall(
      address(srcChain.chain.router), abi.encodeWithSelector(Router.ccipSend.selector), abi.encode(mockMessageId)
    );
    // get fill id
    bytes32 fillId =
      srcChain.tokenPool.computeFillId(mockMessageId, sourceAmount - expectedFastFee, 18, abi.encode(alice));
    vm.startPrank(alice);
    srcChain.stablecoin.approve(address(srcChain.tokenPool), sourceAmount);
    vm.expectEmit();
    emit IFastTransferPool.FastTransferRequested(
      dstChain.chain.chainSelector,
      fillId,
      mockMessageId,
      sourceAmount - expectedFastFee,
      18,
      expectedFastFee,
      0,
      abi.encode(address(dstChain.tokenPool)),
      abi.encode(alice)
    );
    bytes32 settlementId = srcChain.tokenPool.ccipSendToken{value: quote.ccipSettlementFee}(
      dstChain.chain.chainSelector, sourceAmount, expectedFastFee, abi.encode(alice), address(0), ""
    );
    vm.stopPrank();

    assertEq(settlementId, mockMessageId);
    assertEq(srcChain.stablecoin.balanceOf(alice), aliceBalanceBefore - 1e18, "test_CcipSendToken::2");
    assertEq(srcChain.stablecoin.balanceOf(admin), adminBalanceBefore, "test_CcipSendToken::3");
  }

  function test_FastFill() public {
    bytes32 mockMessageId = keccak256("mockMessageId");
    address filler = makeAddr("filler");
    deal(address(srcChain.stablecoin), filler, 1e18);
    bytes32 expectedFillId = srcChain.tokenPool.computeFillId(mockMessageId, 1e18, 18, abi.encode(alice));
    vm.startPrank(filler);
    srcChain.stablecoin.approve(address(srcChain.tokenPool), 1e18);
    vm.expectEmit();
    emit IFastTransferPool.FastTransferFilled(expectedFillId, mockMessageId, filler, 1e18, alice);
    srcChain.tokenPool.fastFill(expectedFillId, mockMessageId, dstChain.chain.chainSelector, 1e18, 18, alice);
    vm.stopPrank();

    assertEq(srcChain.stablecoin.balanceOf(filler), 0, "test_FastFill::1");
    assertEq(srcChain.stablecoin.balanceOf(alice), 1e18, "test_FastFill::2");
  }

  function test_CcipReceieve() public {
    vm.startPrank(admin);
    srcChain.governor.grantRole(srcChain.governor.MINTER_ROLE(), admin);
    srcChain.governor.mint(alice, 2e18); // Alice has tokens to transfer
    vm.stopPrank();

    address filler = makeAddr("filler");
    deal(address(srcChain.stablecoin), filler, 2e18);

    uint256 transferAmount = 1e18;
    bytes memory receiverBytes = abi.encode(bob);

    // Step 2: Alice requests fast transfer
    bytes32 mockMessageId = keccak256("fastTransferMessage");
    vm.mockCall(
      address(srcChain.chain.router), abi.encodeWithSelector(Router.ccipSend.selector), abi.encode(mockMessageId)
    );

    vm.startPrank(alice);
    srcChain.stablecoin.approve(address(srcChain.tokenPool), transferAmount);

    IFastTransferPool.Quote memory quote = srcChain.tokenPool.getCcipSendTokenFee(
      dstChain.chain.chainSelector, transferAmount, receiverBytes, address(0), ""
    );

    bytes32 settlementId = srcChain.tokenPool.ccipSendToken{value: quote.ccipSettlementFee}(
      dstChain.chain.chainSelector, transferAmount, quote.fastTransferFee, receiverBytes, address(0), ""
    );
    vm.stopPrank();

    // Verify tokens were burned from Alice
    assertEq(srcChain.stablecoin.balanceOf(alice), 1e18, "test_CcipReceieve::1");

    // Filler provides fast fill on source chain (fills locally)
    // Calculate the amount after deducting fast transfer fee to match settlement calculation
    uint256 fastTransferFee = (transferAmount * 100) / 10_000; // 1% fee
    uint256 netAmount = transferAmount - fastTransferFee;
    bytes32 fillId = srcChain.tokenPool.computeFillId(settlementId, netAmount, 18, abi.encode(bob));

    vm.startPrank(filler);
    srcChain.stablecoin.approve(address(srcChain.tokenPool), transferAmount);
    srcChain.tokenPool.fastFill(fillId, settlementId, dstChain.chain.chainSelector, netAmount, 18, bob);
    vm.stopPrank();

    // Verify filler paid tokens and bob received them
    assertEq(srcChain.stablecoin.balanceOf(filler), 2e18 - netAmount, "test_CcipReceieve::2");
    assertEq(srcChain.stablecoin.balanceOf(bob), netAmount, "test_CcipReceieve::3");

    // Create settlement message that arrives via CCIP
    // This represents the message that would be sent from the destination chain
    // to settle the fast transfer and compensate the filler
    FastTransferTokenPoolAbstract.MintMessage memory mintMessage = FastTransferTokenPoolAbstract.MintMessage({
      sourceAmount: transferAmount,
      sourceDecimals: 18,
      fastTransferFillerFeeBps: 100,
      fastTransferPoolFeeBps: 0,
      receiver: abi.encode(bob)
    });
    Client.Any2EVMMessage memory settlementMessage = Client.Any2EVMMessage({
      messageId: settlementId,
      sourceChainSelector: dstChain.chain.chainSelector,
      sender: abi.encode(address(dstChain.tokenPool)),
      data: abi.encode(mintMessage),
      destTokenAmounts: new Client.EVMTokenAmount[](0)
    });
    // Settlement occurs when CCIP message arrives
    vm.expectEmit(true, true, true, true);
    emit IFastTransferPool.FastTransferSettled(
      fillId, settlementId, transferAmount, 0, IFastTransferPool.FillState.FILLED
    );

    // Prank as router to simulate CCIP message delivery
    vm.prank(address(srcChain.chain.router));
    srcChain.tokenPool.ccipReceive(settlementMessage);

    // Verify settlement - filler should be compensated
    // During settlement, the filler receives the full settlement amount (1e18)
    // Since they already spent netAmount (0.99e18) for the fast fill, they should get the full amount back
    // Final balance: (2e18 - 0.99e18) + 1e18 = 2.01e18 (they earn the fast transfer fee)
    assertEq(srcChain.stablecoin.balanceOf(filler), 2e18 - netAmount + transferAmount, "test_CcipReceieve::4");
    assertEq(srcChain.stablecoin.balanceOf(bob), netAmount, "test_CcipReceieve::5");
    assertEq(srcChain.stablecoin.balanceOf(alice), 1e18, "test_CcipReceieve::6");
  }

  function test_getAccumulatedPoolFees() public {
    // Mint some tokens to the pool
    vm.startPrank(admin);
    srcChain.governor.grantRole(srcChain.governor.MINTER_ROLE(), admin);
    srcChain.governor.mint(address(srcChain.tokenPool), 100e18);
    vm.stopPrank();

    // Check accumulated fees
    uint256 accumulatedFees = srcChain.tokenPool.getAccumulatedPoolFees();
    assertEq(accumulatedFees, 100e18, "test_getAccumulatedPoolFees::1");
  }
}
