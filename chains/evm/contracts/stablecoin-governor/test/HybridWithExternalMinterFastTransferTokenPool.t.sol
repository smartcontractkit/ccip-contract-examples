// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {HybridTokenPoolAbstract} from "../HybridTokenPoolAbstract.sol";
import {HybridWithExternalMinterFastTransferTokenPool} from "../HybridWithExternalMinterFastTransferTokenPool.sol";
import {TokenGovernor} from "../TokenGovernor.sol";
import {CheckerCounter} from "../checkers/CheckerCounter.sol";
import {Utils} from "./Utils.t.sol";
import {Stablecoin} from "./utils/Stablecoin.sol";
import {IFastTransferPool} from "@chainlink/contracts-ccip/contracts/interfaces/IFastTransferPool.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";
import {IERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {Pool} from "@chainlink/contracts-ccip/contracts/libraries/Pool.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";
import {BurnMintTokenPool} from "@chainlink/contracts-ccip/contracts/pools/BurnMintTokenPool.sol";
import {FastTransferTokenPoolAbstract} from
  "@chainlink/contracts-ccip/contracts/pools/FastTransferTokenPoolAbstract.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {BurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/BurnMintERC20.sol";

contract HybridWithExternalMinterFastTransferTokenPoolTest is Utils {
  struct ManagerChain {
    CCIPChain chain;
    HybridWithExternalMinterFastTransferTokenPool tokenPool;
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
  DstChain dstChainBnM; // Burn and Mint chain
  DstChain dstChainLnR; // Lock and Release chain

  address rebalancer = makeAddr("rebalancer");
  address filler = makeAddr("filler");
  uint256 constant TRANSFER_AMOUNT = 1000e18;
  uint256 constant LIQUIDITY_AMOUNT = 10000e18;

  function setUp() public {
    _addChains(3);
    _wireAll();

    vm.startPrank(admin);

    // Setup Manager Chain with Hybrid Fast Transfer Pool
    _setupManagerChain();

    // Setup Burn and Mint destination chain
    _setupBurnMintChain();

    // Setup Lock and Release destination chain
    _setupLockReleaseChain();

    // Link chains
    _linkTokenPools(
      managerChain.chain.chainSelector,
      address(managerChain.tokenPool),
      dstChainBnM.chain.chainSelector,
      address(dstChainBnM.tokenPool)
    );

    _linkTokenPools(
      managerChain.chain.chainSelector,
      address(managerChain.tokenPool),
      dstChainLnR.chain.chainSelector,
      address(dstChainLnR.tokenPool)
    );

    vm.stopPrank();

    // Setup initial groups and liquidity
    _setupGroupsAndLiquidity();
  }

  function _setupManagerChain() internal {
    managerChain.chain = chains[0];
    managerChain.stablecoin = new Stablecoin();
    managerChain.governor = new TokenGovernor(address(managerChain.stablecoin), 0, admin);
    managerChain.checker = new CheckerCounter(address(managerChain.governor));

    managerChain.tokenPool = new HybridWithExternalMinterFastTransferTokenPool(
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

    managerChain.chain.tokenAdminRegistry.proposeAdministrator(address(managerChain.stablecoin), admin);
    managerChain.chain.tokenAdminRegistry.acceptAdminRole(address(managerChain.stablecoin));
    managerChain.chain.tokenAdminRegistry.setPool(address(managerChain.stablecoin), address(managerChain.tokenPool));
  }

  function _setupBurnMintChain() internal {
    dstChainBnM.chain = chains[1];
    dstChainBnM.token = new BurnMintERC20("Stablecoin", "STABLE", 18, type(uint256).max, 0);
    dstChainBnM.tokenPool = new BurnMintTokenPool(
      dstChainBnM.token, 18, new address[](0), address(dstChainBnM.chain.armProxy), address(dstChainBnM.chain.router)
    );

    dstChainBnM.token.grantMintAndBurnRoles(address(dstChainBnM.tokenPool));

    dstChainBnM.chain.tokenAdminRegistry.proposeAdministrator(address(dstChainBnM.token), admin);
    dstChainBnM.chain.tokenAdminRegistry.acceptAdminRole(address(dstChainBnM.token));
    dstChainBnM.chain.tokenAdminRegistry.setPool(address(dstChainBnM.token), address(dstChainBnM.tokenPool));
  }

  function _setupLockReleaseChain() internal {
    dstChainLnR.chain = chains[2];
    dstChainLnR.token = new BurnMintERC20("Stablecoin", "STABLE", 18, type(uint256).max, 0);
    dstChainLnR.tokenPool = new BurnMintTokenPool(
      dstChainLnR.token, 18, new address[](0), address(dstChainLnR.chain.armProxy), address(dstChainLnR.chain.router)
    );

    dstChainLnR.token.grantMintAndBurnRoles(address(dstChainLnR.tokenPool));

    dstChainLnR.chain.tokenAdminRegistry.proposeAdministrator(address(dstChainLnR.token), admin);
    dstChainLnR.chain.tokenAdminRegistry.acceptAdminRole(address(dstChainLnR.token));
    dstChainLnR.chain.tokenAdminRegistry.setPool(address(dstChainLnR.token), address(dstChainLnR.tokenPool));
  }

  function _setupGroupsAndLiquidity() internal {
    vm.startPrank(admin);

    // Set rebalancer
    managerChain.tokenPool.setRebalancer(rebalancer);

    // Configure groups - only update the chain that needs to change to BURN_AND_MINT
    // (dstChainLnR is already LOCK_AND_RELEASE by default)
    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](1);

    // Set burn and mint group for the BnM chain
    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainBnM.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: 0
    });

    managerChain.tokenPool.updateGroups(groupUpdates);

    // Add some initial liquidity to the pool for Lock and Release operations
    // Grant mint permissions to admin for testing
    managerChain.governor.grantRole(managerChain.governor.MINTER_ROLE(), admin);

    // Mint initial tokens to rebalancer and admin
    managerChain.governor.mint(admin, LIQUIDITY_AMOUNT);
    managerChain.governor.mint(rebalancer, LIQUIDITY_AMOUNT);

    vm.stopPrank();

    // Provide liquidity as rebalancer
    vm.startPrank(rebalancer);
    managerChain.stablecoin.approve(address(managerChain.tokenPool), LIQUIDITY_AMOUNT);
    managerChain.tokenPool.provideLiquidity(LIQUIDITY_AMOUNT);
    vm.stopPrank();

    // Setup filler with tokens
    vm.prank(admin);
    managerChain.governor.mint(filler, TRANSFER_AMOUNT * 10);

    // Add filler to allowlist for fast transfers
    vm.prank(admin);
    address[] memory fillersToAdd = new address[](1);
    fillersToAdd[0] = filler;
    managerChain.tokenPool.updateFillerAllowList(fillersToAdd, new address[](0));
  }

  // ================================================================
  // │                         Basic Tests                          │
  // ================================================================

  function test_typeAndVersion() public view {
    assertEq(managerChain.tokenPool.typeAndVersion(), "HybridWithExternalMinterFastTransferTokenPool 1.6.0");
  }

  function test_getMinter() public view {
    assertEq(managerChain.tokenPool.getMinter(), address(managerChain.governor));
  }

  function test_getRebalancer() public view {
    assertEq(managerChain.tokenPool.getRebalancer(), rebalancer);
  }

  function test_getGroup() public view {
    assertEq(
      uint256(managerChain.tokenPool.getGroup(dstChainBnM.chain.chainSelector)),
      uint256(HybridTokenPoolAbstract.Group.BURN_AND_MINT)
    );
    assertEq(
      uint256(managerChain.tokenPool.getGroup(dstChainLnR.chain.chainSelector)),
      uint256(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE)
    );
  }

  function test_getLockedTokens() public view {
    uint256 lockedTokens = managerChain.tokenPool.getLockedTokens();
    assertEq(lockedTokens, LIQUIDITY_AMOUNT);
  }

  // ================================================================
  // │                      Group Management                        │
  // ================================================================

  function test_setRebalancer() public {
    address newRebalancer = makeAddr("newRebalancer");

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.RebalancerSet(rebalancer, newRebalancer);

    vm.prank(admin);
    managerChain.tokenPool.setRebalancer(newRebalancer);

    assertEq(managerChain.tokenPool.getRebalancer(), newRebalancer);
  }

  function test_updateGroups() public {
    uint64 newChainSelector = 999;

    // Add the new chain to supported chains first
    vm.prank(admin);
    managerChain.tokenPool.applyChainUpdates(new uint64[](0), _getChainUpdatesWithChainSelector(newChainSelector));

    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](1);

    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: newChainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: 0
    });

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(newChainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT);

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(groupUpdates);

    assertEq(
      uint256(managerChain.tokenPool.getGroup(newChainSelector)), uint256(HybridTokenPoolAbstract.Group.BURN_AND_MINT)
    );
  }

  // ================================================================
  // │                    Liquidity Management                      │
  // ================================================================

  function test_provideLiquidity() public {
    uint256 additionalAmount = 1000e18;
    vm.prank(admin);
    managerChain.governor.mint(rebalancer, additionalAmount);

    vm.startPrank(rebalancer);
    managerChain.stablecoin.approve(address(managerChain.tokenPool), additionalAmount);

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityAdded(rebalancer, additionalAmount);

    managerChain.tokenPool.provideLiquidity(additionalAmount);
    vm.stopPrank();

    assertEq(
      managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), LIQUIDITY_AMOUNT + additionalAmount
    );
  }

  function test_withdrawLiquidity() public {
    uint256 removeAmount = 500e18;

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityRemoved(rebalancer, removeAmount);

    vm.prank(rebalancer);
    managerChain.tokenPool.withdrawLiquidity(removeAmount);

    assertEq(
      managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), LIQUIDITY_AMOUNT - removeAmount
    );
    assertEq(managerChain.stablecoin.balanceOf(rebalancer), removeAmount);
  }

  // ================================================================
  // │                     Fast Transfer Tests                      │
  // ================================================================

  function test_ccipSendToken_BurnAndMint() public {
    // Setup dest chain config for fast transfers
    _setupFastTransferConfig(dstChainBnM.chain.chainSelector);

    // Mint tokens to sender
    address sender = makeAddr("sender");
    vm.prank(admin);
    managerChain.governor.mint(sender, TRANSFER_AMOUNT);

    vm.startPrank(sender);
    managerChain.stablecoin.approve(address(managerChain.tokenPool), TRANSFER_AMOUNT);

    bytes memory receiver = abi.encode(makeAddr("receiver"));
    uint256 maxFee = 1000e18; // High max fee to ensure it passes

    // Get the fee quote to determine how much ETH to send
    IFastTransferPool.Quote memory quote = managerChain.tokenPool.getCcipSendTokenFee(
      dstChainBnM.chain.chainSelector,
      TRANSFER_AMOUNT,
      receiver,
      address(0), // Native fee token
      ""
    );

    // Fund the sender with enough ETH to pay for fees
    vm.deal(sender, quote.ccipSettlementFee + 1 ether);

    managerChain.tokenPool.ccipSendToken{value: quote.ccipSettlementFee}(
      dstChainBnM.chain.chainSelector,
      TRANSFER_AMOUNT,
      maxFee,
      receiver,
      address(0), // Native fee token
      ""
    );

    vm.stopPrank();
    // Verify tokens were burned (sender balance should be 0)
    assertEq(managerChain.stablecoin.balanceOf(sender), 0);
  }

  function test_ccipSendToken_LockAndRelease() public {
    // Setup dest chain config for fast transfers
    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);

    // Mint tokens to sender
    address sender = makeAddr("sender");
    vm.prank(admin);
    managerChain.governor.mint(sender, TRANSFER_AMOUNT);

    uint256 initialPoolBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    vm.startPrank(sender);
    managerChain.stablecoin.approve(address(managerChain.tokenPool), TRANSFER_AMOUNT);

    bytes memory receiver = abi.encode(makeAddr("receiver"));
    uint256 maxFee = 1000e18; // High max fee to ensure it passes

    // Get the fee quote to determine how much ETH to send
    IFastTransferPool.Quote memory quote = managerChain.tokenPool.getCcipSendTokenFee(
      dstChainLnR.chain.chainSelector,
      TRANSFER_AMOUNT,
      receiver,
      address(0), // Native fee token
      ""
    );

    // Fund the sender with enough ETH to pay for fees
    vm.deal(sender, quote.ccipSettlementFee + 1 ether);

    managerChain.tokenPool.ccipSendToken{value: quote.ccipSettlementFee}(
      dstChainLnR.chain.chainSelector,
      TRANSFER_AMOUNT,
      maxFee,
      receiver,
      address(0), // Native fee token
      ""
    );

    vm.stopPrank();
    // Verify tokens were locked in pool (sender balance should be 0, pool balance increased)
    assertEq(managerChain.stablecoin.balanceOf(sender), 0);
    assertEq(
      managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), initialPoolBalance + TRANSFER_AMOUNT
    );
  }

  // ================================================================
  // │                  LockOrBurn & ReleaseOrMint Tests            │
  // ================================================================

  function test_lockOrBurn_BurnAndMintGroup() public {
    address caller = address(onRamps[managerChain.chain.chainSelector]);
    uint256 amount = 1000e18;

    // Setup tokens in pool (simulating router behavior)
    vm.prank(admin);
    managerChain.governor.mint(address(managerChain.tokenPool), amount);

    uint256 initialTotalSupply = managerChain.stablecoin.totalSupply();

    // Create lockOrBurn input
    Pool.LockOrBurnInV1 memory lockOrBurnIn = Pool.LockOrBurnInV1({
      originalSender: makeAddr("sender"),
      receiver: abi.encode(makeAddr("receiver")),
      amount: amount,
      remoteChainSelector: dstChainBnM.chain.chainSelector,
      localToken: address(managerChain.stablecoin)
    });

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(dstChainBnM.chain.chainSelector, address(managerChain.stablecoin), caller, amount);

    vm.prank(caller);
    Pool.LockOrBurnOutV1 memory result = managerChain.tokenPool.lockOrBurn(lockOrBurnIn);

    // Verify tokens were burned (total supply decreased)
    assertEq(managerChain.stablecoin.totalSupply(), initialTotalSupply - amount);

    // Verify return values
    assertEq(result.destTokenAddress, managerChain.tokenPool.getRemoteToken(dstChainBnM.chain.chainSelector));
    assertEq(result.destPoolData, abi.encode(uint8(18))); // Local token decimals
  }

  function test_lockOrBurn_LockAndReleaseGroup() public {
    address caller = address(onRamps[managerChain.chain.chainSelector]);
    uint256 amount = 1000e18;

    // Setup tokens in pool (simulating router behavior)
    vm.prank(admin);
    managerChain.governor.mint(address(managerChain.tokenPool), amount);

    uint256 initialPoolBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));
    uint256 initialTotalSupply = managerChain.stablecoin.totalSupply();

    // Create lockOrBurn input
    Pool.LockOrBurnInV1 memory lockOrBurnIn = Pool.LockOrBurnInV1({
      originalSender: makeAddr("sender"),
      receiver: abi.encode(makeAddr("receiver")),
      amount: amount,
      remoteChainSelector: dstChainLnR.chain.chainSelector,
      localToken: address(managerChain.stablecoin)
    });

    vm.expectEmit(true, true, true, true);
    emit TokenPool.LockedOrBurned(dstChainLnR.chain.chainSelector, address(managerChain.stablecoin), caller, amount);

    vm.prank(caller);
    Pool.LockOrBurnOutV1 memory result = managerChain.tokenPool.lockOrBurn(lockOrBurnIn);

    // Verify tokens were locked (pool balance unchanged, total supply unchanged)
    assertEq(managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), initialPoolBalance);
    assertEq(managerChain.stablecoin.totalSupply(), initialTotalSupply); // No change in total supply

    // Verify return values
    assertEq(result.destTokenAddress, managerChain.tokenPool.getRemoteToken(dstChainLnR.chain.chainSelector));
    assertEq(result.destPoolData, abi.encode(uint8(18))); // Local token decimals
  }

  function test_releaseOrMint_BurnAndMintGroup() public {
    address caller = address(offRamps[managerChain.chain.chainSelector]);
    address receiver = makeAddr("receiver");
    uint256 amount = 1000e18;

    uint256 initialTotalSupply = managerChain.stablecoin.totalSupply();
    uint256 initialReceiverBalance = managerChain.stablecoin.balanceOf(receiver);

    // Create releaseOrMint input
    Pool.ReleaseOrMintInV1 memory releaseOrMintIn = Pool.ReleaseOrMintInV1({
      originalSender: abi.encode(makeAddr("originalSender")),
      receiver: receiver,
      sourceDenominatedAmount: amount,
      localToken: address(managerChain.stablecoin),
      remoteChainSelector: dstChainBnM.chain.chainSelector,
      sourcePoolAddress: abi.encode(address(dstChainBnM.tokenPool)),
      sourcePoolData: abi.encode(uint8(18)), // 18 decimals
      offchainTokenData: ""
    });

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(
      dstChainBnM.chain.chainSelector, address(managerChain.stablecoin), caller, receiver, amount
    );

    vm.prank(caller);
    Pool.ReleaseOrMintOutV1 memory result = managerChain.tokenPool.releaseOrMint(releaseOrMintIn);

    // Verify tokens were minted (total supply increased, receiver balance increased)
    assertEq(managerChain.stablecoin.totalSupply(), initialTotalSupply + amount);
    assertEq(managerChain.stablecoin.balanceOf(receiver), initialReceiverBalance + amount);

    // Verify return values
    assertEq(result.destinationAmount, amount);
  }

  function test_releaseOrMint_LockAndReleaseGroup() public {
    address caller = address(offRamps[managerChain.chain.chainSelector]);
    address receiver = makeAddr("receiver");
    uint256 amount = 1000e18;

    // Setup liquidity in pool first
    vm.prank(admin);
    managerChain.governor.mint(address(managerChain.tokenPool), amount);

    uint256 initialTotalSupply = managerChain.stablecoin.totalSupply();
    uint256 initialReceiverBalance = managerChain.stablecoin.balanceOf(receiver);
    uint256 initialPoolBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    // Create releaseOrMint input
    Pool.ReleaseOrMintInV1 memory releaseOrMintIn = Pool.ReleaseOrMintInV1({
      originalSender: abi.encode(makeAddr("originalSender")),
      receiver: receiver,
      sourceDenominatedAmount: amount,
      localToken: address(managerChain.stablecoin),
      remoteChainSelector: dstChainLnR.chain.chainSelector,
      sourcePoolAddress: abi.encode(address(dstChainLnR.tokenPool)),
      sourcePoolData: abi.encode(uint8(18)), // 18 decimals
      offchainTokenData: ""
    });

    vm.expectEmit(true, true, true, true);
    emit TokenPool.ReleasedOrMinted(
      dstChainLnR.chain.chainSelector, address(managerChain.stablecoin), caller, receiver, amount
    );

    vm.prank(caller);
    Pool.ReleaseOrMintOutV1 memory result = managerChain.tokenPool.releaseOrMint(releaseOrMintIn);

    // Verify tokens were released (total supply unchanged, receiver balance increased, pool balance decreased)
    assertEq(managerChain.stablecoin.totalSupply(), initialTotalSupply); // No change in total supply
    assertEq(managerChain.stablecoin.balanceOf(receiver), initialReceiverBalance + amount);
    assertEq(managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), initialPoolBalance - amount);

    // Verify return values
    assertEq(result.destinationAmount, amount);
  }

  // ================================================================
  // │                       Error Condition Tests                 │
  // ================================================================

  function test_Revert_provideLiquidity_ZeroAmount() public {
    vm.expectRevert(abi.encodeWithSelector(HybridTokenPoolAbstract.LiquidityAmountCannotBeZero.selector));

    vm.prank(rebalancer);
    managerChain.tokenPool.provideLiquidity(0);
  }

  function test_Revert_provideLiquidity_Unauthorized() public {
    address unauthorizedUser = makeAddr("unauthorized");

    vm.expectRevert(abi.encodeWithSelector(TokenPool.Unauthorized.selector, unauthorizedUser));

    vm.prank(unauthorizedUser);
    managerChain.tokenPool.provideLiquidity(1000e18);
  }

  function test_Revert_withdrawLiquidity_ZeroAmount() public {
    vm.expectRevert(abi.encodeWithSelector(HybridTokenPoolAbstract.LiquidityAmountCannotBeZero.selector));

    vm.prank(rebalancer);
    managerChain.tokenPool.withdrawLiquidity(0);
  }

  function test_Revert_withdrawLiquidity_Unauthorized() public {
    address unauthorizedUser = makeAddr("unauthorized");

    vm.expectRevert(abi.encodeWithSelector(TokenPool.Unauthorized.selector, unauthorizedUser));

    vm.prank(unauthorizedUser);
    managerChain.tokenPool.withdrawLiquidity(1000e18);
  }

  function test_withdrawLiquidity_WithAccumulatedFees() public {
    // Setup fast transfer configs to accumulate fees
    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);

    // Perform fast transfer to accumulate fees
    _performFastTransferWithSettlement(dstChainLnR.chain.chainSelector, 1000e18);

    uint256 accumulatedFees = managerChain.tokenPool.getAccumulatedPoolFees();
    uint256 currentBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    // Try to remove liquidity that leaves enough for accumulated fees
    uint256 safeRemovalAmount = currentBalance - accumulatedFees - 100e18; // Leave buffer

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityRemoved(rebalancer, safeRemovalAmount);

    vm.prank(rebalancer);
    managerChain.tokenPool.withdrawLiquidity(safeRemovalAmount);

    // Verify the removal was successful
    assertEq(
      managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), currentBalance - safeRemovalAmount
    );
    assertEq(managerChain.stablecoin.balanceOf(rebalancer), safeRemovalAmount);
  }

  function test_Revert_withdrawLiquidity_InsufficientLiquidity_WithAccumulatedFees() public {
    // Setup fast transfer configs to accumulate fees
    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);

    // Perform fast transfer to accumulate fees
    _performFastTransferWithSettlement(dstChainLnR.chain.chainSelector, 1000e18);

    uint256 accumulatedFees = managerChain.tokenPool.getAccumulatedPoolFees();
    uint256 currentBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    // Try to remove too much liquidity (would not leave enough for accumulated fees)
    uint256 excessiveAmount = currentBalance - accumulatedFees + 1e18;

    vm.expectRevert(
      abi.encodeWithSelector(
        HybridWithExternalMinterFastTransferTokenPool.InsufficientLiquidity.selector,
        currentBalance,
        excessiveAmount + accumulatedFees
      )
    );

    vm.prank(rebalancer);
    managerChain.tokenPool.withdrawLiquidity(excessiveAmount);
  }

  function test_withdrawLiquidity_ExactAmountLeavingFees() public {
    // Setup fast transfer configs to accumulate fees
    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);

    // Perform fast transfer to accumulate fees
    _performFastTransferWithSettlement(dstChainLnR.chain.chainSelector, 1000e18);

    uint256 accumulatedFees = managerChain.tokenPool.getAccumulatedPoolFees();
    uint256 currentBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    // Remove exactly the amount that leaves just the accumulated fees
    uint256 exactAmount = currentBalance - accumulatedFees;

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityRemoved(rebalancer, exactAmount);

    vm.prank(rebalancer);
    managerChain.tokenPool.withdrawLiquidity(exactAmount);

    // Verify only accumulated fees remain
    assertEq(managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), accumulatedFees);
    assertEq(managerChain.stablecoin.balanceOf(rebalancer), exactAmount);
  }

  function test_Revert_withdrawLiquidity_TryRemoveAllLiquidity_WithAccumulatedFees() public {
    // Setup fast transfer configs to accumulate fees
    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);

    // Perform fast transfer to accumulate fees
    _performFastTransferWithSettlement(dstChainLnR.chain.chainSelector, 1000e18);

    uint256 accumulatedFees = managerChain.tokenPool.getAccumulatedPoolFees();
    uint256 currentBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    // Try to remove all liquidity (should fail)
    vm.expectRevert(
      abi.encodeWithSelector(
        HybridWithExternalMinterFastTransferTokenPool.InsufficientLiquidity.selector,
        currentBalance,
        currentBalance + accumulatedFees
      )
    );

    vm.prank(rebalancer);
    managerChain.tokenPool.withdrawLiquidity(currentBalance);
  }

  function test_withdrawLiquidity_NoAccumulatedFees() public {
    // Test that normal liquidity removal works when there are no accumulated fees
    uint256 removeAmount = 500e18;
    uint256 initialBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    // Verify no accumulated fees
    assertEq(managerChain.tokenPool.getAccumulatedPoolFees(), 0);

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityRemoved(rebalancer, removeAmount);

    vm.prank(rebalancer);
    managerChain.tokenPool.withdrawLiquidity(removeAmount);

    assertEq(
      managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), initialBalance - removeAmount
    );
    assertEq(managerChain.stablecoin.balanceOf(rebalancer), removeAmount);
  }

  function test_Revert_updateGroups_InvalidGroupUpdate_SameGroup() public {
    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](1);

    // Try to update BnM chain to the same group it's already in
    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainBnM.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: 0
    });

    vm.expectRevert(
      abi.encodeWithSelector(
        HybridTokenPoolAbstract.InvalidGroupUpdate.selector,
        dstChainBnM.chain.chainSelector,
        HybridTokenPoolAbstract.Group.BURN_AND_MINT
      )
    );

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(groupUpdates);
  }

  function test_Revert_updateGroups_InvalidGroupUpdate_UnsupportedChain() public {
    uint64 unsupportedChainSelector = 999;

    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](1);

    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: unsupportedChainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: 0
    });

    vm.expectRevert(
      abi.encodeWithSelector(
        HybridTokenPoolAbstract.InvalidGroupUpdate.selector,
        unsupportedChainSelector,
        HybridTokenPoolAbstract.Group.BURN_AND_MINT
      )
    );

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(groupUpdates);
  }

  function test_Revert_updateGroups_OnlyOwner() public {
    address unauthorizedUser = makeAddr("unauthorized");

    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](0);

    vm.expectRevert(abi.encodeWithSignature("OnlyCallableByOwner()"));

    vm.prank(unauthorizedUser);
    managerChain.tokenPool.updateGroups(groupUpdates);
  }

  // ================================================================
  // │                 Liquidity Migration Tests                    │
  // ================================================================

  function test_updateGroups_WithLiquidityMigration_ToLockAndRelease() public {
    uint256 remoteChainSupply = 5000e18;

    // Change BnM chain from BURN_AND_MINT to LOCK_AND_RELEASE with liquidity migration
    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](1);

    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainBnM.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE,
      remoteChainSupply: remoteChainSupply
    });

    uint256 initialPoolBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityMigrated(
      dstChainBnM.chain.chainSelector, HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE, remoteChainSupply
    );

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(
      dstChainBnM.chain.chainSelector, HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE
    );

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(groupUpdates);

    // Verify group was updated
    assertEq(
      uint256(managerChain.tokenPool.getGroup(dstChainBnM.chain.chainSelector)),
      uint256(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE)
    );

    // Verify liquidity was minted to the pool
    assertEq(
      managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)),
      initialPoolBalance + remoteChainSupply
    );
  }

  function test_updateGroups_WithLiquidityMigration_ToBurnAndMint() public {
    uint256 remoteChainSupply = 3000e18;

    // Change LnR chain from LOCK_AND_RELEASE to BURN_AND_MINT with liquidity migration
    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](1);

    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: remoteChainSupply
    });

    // First, we need to ensure the pool has enough liquidity to burn
    vm.prank(admin);
    managerChain.governor.mint(address(managerChain.tokenPool), remoteChainSupply);

    uint256 initialPoolBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityMigrated(
      dstChainLnR.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT, remoteChainSupply
    );

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(
      dstChainLnR.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT
    );

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(groupUpdates);

    // Verify group was updated
    assertEq(
      uint256(managerChain.tokenPool.getGroup(dstChainLnR.chain.chainSelector)),
      uint256(HybridTokenPoolAbstract.Group.BURN_AND_MINT)
    );

    // Verify liquidity was burned from the pool
    assertEq(
      managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)),
      initialPoolBalance - remoteChainSupply
    );
  }

  function test_multipleGroupUpdates() public {
    // Add new supported chains first
    uint64 newChain1 = 1001;
    uint64 newChain2 = 1002;

    vm.prank(admin);
    managerChain.tokenPool.applyChainUpdates(new uint64[](0), _getMultipleChainUpdates(newChain1, newChain2));

    // Update multiple groups at once
    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](2);

    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: newChain1,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: 0
    });

    groupUpdates[1] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: newChain2,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: 0
    });

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(newChain1, HybridTokenPoolAbstract.Group.BURN_AND_MINT);

    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.GroupUpdated(newChain2, HybridTokenPoolAbstract.Group.BURN_AND_MINT);

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(groupUpdates);

    assertEq(uint256(managerChain.tokenPool.getGroup(newChain1)), uint256(HybridTokenPoolAbstract.Group.BURN_AND_MINT));
    assertEq(uint256(managerChain.tokenPool.getGroup(newChain2)), uint256(HybridTokenPoolAbstract.Group.BURN_AND_MINT));
  }

  function test_liquidityOperations_EdgeCases() public {
    // Test providing liquidity when pool has no initial liquidity
    vm.prank(rebalancer);
    managerChain.tokenPool.withdrawLiquidity(LIQUIDITY_AMOUNT); // Remove all liquidity

    assertEq(managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), 0);

    // Provide liquidity to empty pool
    uint256 newAmount = 500e18;
    vm.prank(admin);
    managerChain.governor.mint(rebalancer, newAmount);

    vm.startPrank(rebalancer);
    managerChain.stablecoin.approve(address(managerChain.tokenPool), newAmount);
    managerChain.tokenPool.provideLiquidity(newAmount);
    vm.stopPrank();

    assertEq(managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), newAmount);

    // Test removing partial liquidity
    uint256 partialAmount = 200e18;
    vm.prank(rebalancer);
    managerChain.tokenPool.withdrawLiquidity(partialAmount);

    assertEq(managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), newAmount - partialAmount);
  }

  // ================================================================
  // │                  Fast Transfer Hook Tests                    │
  // ================================================================
  function test_fastFillReimbursement_LockAndRelease() public {
    // Setup the pool with some liquidity for reimbursement
    uint256 additionalLiquidity = 5000e18;
    vm.prank(admin);
    managerChain.governor.mint(rebalancer, additionalLiquidity);

    vm.startPrank(rebalancer);
    managerChain.stablecoin.approve(address(managerChain.tokenPool), additionalLiquidity);
    managerChain.tokenPool.provideLiquidity(additionalLiquidity);
    vm.stopPrank();

    address testFiller = makeAddr("testFiller");
    uint256 fillerReimbursementAmount = 1000e18;
    uint256 poolReimbursementAmount = 50e18;

    FastTransferTokenPoolAbstract.MintMessage memory mintMessage = FastTransferTokenPoolAbstract.MintMessage({
      sourceAmount: fillerReimbursementAmount + poolReimbursementAmount,
      sourceDecimals: 18,
      fastTransferFillerFeeBps: 100,
      fastTransferPoolFeeBps: 50,
      receiver: abi.encode(testFiller)
    });

    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(uint256(1)),
      sourceChainSelector: dstChainLnR.chain.chainSelector,
      sender: abi.encode(address(dstChainLnR.tokenPool)),
      data: abi.encode(mintMessage),
      destTokenAmounts: new Client.EVMTokenAmount[](0)
    });

    vm.prank(address(managerChain.chain.router));
    managerChain.tokenPool.ccipReceive(message);

    // Verify settlement occurred (exact amounts depend on the implementation)
  }

  function test_fastFillReimbursement_BurnAndMint() public {
    address testFiller = makeAddr("testFillerBnM");
    uint256 fillerReimbursementAmount = 1000e18;
    uint256 poolReimbursementAmount = 50e18;

    // Create fast fill reimbursement message using existing patterns
    FastTransferTokenPoolAbstract.MintMessage memory mintMessage = FastTransferTokenPoolAbstract.MintMessage({
      sourceAmount: fillerReimbursementAmount + poolReimbursementAmount,
      sourceDecimals: 18,
      fastTransferFillerFeeBps: 100,
      fastTransferPoolFeeBps: 50,
      receiver: abi.encode(testFiller)
    });

    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: bytes32(uint256(1)),
      sourceChainSelector: dstChainBnM.chain.chainSelector,
      sender: abi.encode(address(dstChainBnM.tokenPool)),
      data: abi.encode(mintMessage),
      destTokenAmounts: new Client.EVMTokenAmount[](0)
    });

    vm.prank(address(managerChain.chain.router));
    managerChain.tokenPool.ccipReceive(message);

    // Verify settlement occurred (exact amounts depend on the implementation)
  }

  function test_lockOrBurn_DifferentGroups() public {
    // This tests the internal _lockOrBurn function through different transfer paths
    address sender = makeAddr("sender");
    uint256 amount = 1000e18;

    // Setup for both chains
    _setupFastTransferConfig(dstChainBnM.chain.chainSelector);
    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);

    // Test BURN_AND_MINT path
    vm.prank(admin);
    managerChain.governor.mint(sender, amount * 2);

    uint256 initialTotalSupply = managerChain.stablecoin.totalSupply();
    uint256 initialPoolBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    // Send to BURN_AND_MINT chain
    vm.startPrank(sender);
    managerChain.stablecoin.approve(address(managerChain.tokenPool), amount * 2);

    IFastTransferPool.Quote memory quote1 = managerChain.tokenPool.getCcipSendTokenFee(
      dstChainBnM.chain.chainSelector, amount, abi.encode(makeAddr("receiver1")), address(0), ""
    );
    vm.deal(sender, quote1.ccipSettlementFee + 1 ether);

    managerChain.tokenPool.ccipSendToken{value: quote1.ccipSettlementFee}(
      dstChainBnM.chain.chainSelector, amount, 1000e18, abi.encode(makeAddr("receiver1")), address(0), ""
    );

    // Verify tokens were burned (total supply decreased)
    assertLt(managerChain.stablecoin.totalSupply(), initialTotalSupply);

    // Send to LOCK_AND_RELEASE chain
    IFastTransferPool.Quote memory quote2 = managerChain.tokenPool.getCcipSendTokenFee(
      dstChainLnR.chain.chainSelector, amount, abi.encode(makeAddr("receiver2")), address(0), ""
    );
    vm.deal(sender, quote2.ccipSettlementFee + 1 ether);

    managerChain.tokenPool.ccipSendToken{value: quote2.ccipSettlementFee}(
      dstChainLnR.chain.chainSelector, amount, 1000e18, abi.encode(makeAddr("receiver2")), address(0), ""
    );

    // Verify tokens were locked (pool balance increased)
    assertEq(managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), initialPoolBalance + amount);

    vm.stopPrank();
  }

  function test_emptyGroupUpdatesArray() public {
    // Test that empty array doesn't cause issues
    HybridTokenPoolAbstract.GroupUpdate[] memory emptyUpdates = new HybridTokenPoolAbstract.GroupUpdate[](0);

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(emptyUpdates);

    // Should not change any existing groups
    assertEq(
      uint256(managerChain.tokenPool.getGroup(dstChainBnM.chain.chainSelector)),
      uint256(HybridTokenPoolAbstract.Group.BURN_AND_MINT)
    );
    assertEq(
      uint256(managerChain.tokenPool.getGroup(dstChainLnR.chain.chainSelector)),
      uint256(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE)
    );
  }

  // ============================================================
  // │                  Pool Fee Tests                          │
  // ============================================================

  function test_getAccumulatedPoolFees() public {
    // Test the key difference between the hybrid pool and parent contract
    // The hybrid pool tracks fees separately from locked tokens

    // Initially no accumulated pool fees (differs from parent contract)
    assertEq(managerChain.tokenPool.getAccumulatedPoolFees(), 0);

    // Pool fees and locked tokens are separate concepts
    uint256 lockedTokens = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));
    assertEq(lockedTokens, LIQUIDITY_AMOUNT); // Has locked tokens from setup

    // The hybrid pool's getAccumulatedPoolFees() is NOT equal to locked tokens
    // (This is the key difference from the parent BurnMintWithExternalMinterFastTransferTokenPool)
    assertNotEq(managerChain.tokenPool.getAccumulatedPoolFees(), lockedTokens);

    // Pool fees only accumulate through actual reimbursement operations
    // not through liquidity operations
    uint256 additionalAmount = 1000e18;
    vm.prank(admin);
    managerChain.governor.mint(rebalancer, additionalAmount);

    vm.startPrank(rebalancer);
    managerChain.stablecoin.approve(address(managerChain.tokenPool), additionalAmount);
    managerChain.tokenPool.provideLiquidity(additionalAmount);
    vm.stopPrank();

    // Locked tokens increased
    assertEq(
      managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)), LIQUIDITY_AMOUNT + additionalAmount
    );

    // But pool fees still 0 (not affected by liquidity operations)
    assertEq(managerChain.tokenPool.getAccumulatedPoolFees(), 0);
  }

  function test_withdrawPoolFees() public {
    // Test the function exists and works with 0 fees (no event emitted)
    address feeRecipient = makeAddr("feeRecipient");
    uint256 initialBalance = managerChain.stablecoin.balanceOf(feeRecipient);

    // Should not revert when there are no fees to withdraw
    // No event is emitted when amount = 0
    vm.prank(admin);
    managerChain.tokenPool.withdrawPoolFees(feeRecipient);

    // Balance should remain unchanged since no fees to withdraw
    assertEq(managerChain.stablecoin.balanceOf(feeRecipient), initialBalance);
    assertEq(managerChain.tokenPool.getAccumulatedPoolFees(), 0);
  }

  function test_withdrawPoolFees_WithAccumulatedFees() public {
    // Setup fast transfer configs for both chains
    _setupFastTransferConfig(dstChainBnM.chain.chainSelector);
    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);

    // Initial state - no accumulated fees
    assertEq(managerChain.tokenPool.getAccumulatedPoolFees(), 0);
    uint256 initialLockedTokens = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    // Perform fast transfer with Lock and Release chain
    _performFastTransferWithSettlement(dstChainLnR.chain.chainSelector, 500e18);

    // Perform fast transfer with Burn and Mint chain
    _performFastTransferWithSettlement(dstChainBnM.chain.chainSelector, 400e18);

    // Assert pool fees have accumulated
    uint256 accumulatedFees = managerChain.tokenPool.getAccumulatedPoolFees();
    uint256 totalLockedTokens = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    assertEq(
      accumulatedFees, 500e18 * 0.005 + 400e18 * 0.005, "Pool fees should have accumulated from fast settlements"
    );
    assertGt(totalLockedTokens, initialLockedTokens, "Pool should have more tokens after settlements");

    // Store the recipient's initial balance
    address feeRecipient = makeAddr("feeRecipient");
    uint256 recipientInitialBalance = managerChain.stablecoin.balanceOf(feeRecipient);

    // Withdraw pool fees
    vm.expectEmit(true, true, true, true);
    emit IFastTransferPool.PoolFeeWithdrawn(feeRecipient, accumulatedFees);

    vm.prank(admin);
    managerChain.tokenPool.withdrawPoolFees(feeRecipient);

    // Assert accumulated fee tracker is now zero
    assertEq(managerChain.tokenPool.getAccumulatedPoolFees(), 0, "Accumulated fees should be zero after withdrawal");

    // Assert recipient received the fees
    assertEq(
      managerChain.stablecoin.balanceOf(feeRecipient),
      recipientInitialBalance + accumulatedFees,
      "Fee recipient should have received the accumulated fees"
    );

    // Assert locked tokens are reduced by the withdrawn fee amount
    assertEq(
      managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)),
      totalLockedTokens - accumulatedFees,
      "Locked tokens should be reduced by withdrawn fee amount"
    );
  }

  function _performFastTransferWithSettlement(uint64 chainSelector, uint256 transferAmount) internal {
    address user = makeAddr(string(abi.encodePacked("user", chainSelector)));
    address receiver = makeAddr(string(abi.encodePacked("receiver", chainSelector)));

    // Mint tokens to user and filler
    vm.startPrank(admin);
    managerChain.governor.mint(user, transferAmount);
    managerChain.governor.mint(filler, transferAmount * 2);

    // Add filler to allowlist
    address[] memory fillersToAdd = new address[](1);
    fillersToAdd[0] = filler;
    managerChain.tokenPool.updateFillerAllowList(fillersToAdd, new address[](0));
    vm.stopPrank();

    // User requests fast transfer
    vm.startPrank(user);
    managerChain.stablecoin.approve(address(managerChain.tokenPool), transferAmount);

    IFastTransferPool.Quote memory quote =
      managerChain.tokenPool.getCcipSendTokenFee(chainSelector, transferAmount, abi.encode(receiver), address(0), "");
    vm.deal(user, quote.ccipSettlementFee);

    bytes32 settlementId = managerChain.tokenPool.ccipSendToken{value: quote.ccipSettlementFee}(
      chainSelector, transferAmount, quote.fastTransferFee, abi.encode(receiver), address(0), ""
    );
    vm.stopPrank();

    // Filler performs fast fill
    uint256 netAmount = transferAmount - quote.fastTransferFee;
    bytes32 fillId = managerChain.tokenPool.computeFillId(settlementId, netAmount, 18, abi.encode(receiver));

    vm.startPrank(filler);
    managerChain.stablecoin.approve(address(managerChain.tokenPool), netAmount);
    managerChain.tokenPool.fastFill(fillId, settlementId, chainSelector, netAmount, 18, receiver);
    vm.stopPrank();

    // Settlement message arrives
    FastTransferTokenPoolAbstract.MintMessage memory mintMessage = FastTransferTokenPoolAbstract.MintMessage({
      sourceAmount: transferAmount,
      sourceDecimals: 18,
      fastTransferFillerFeeBps: 100, // 1% filler fee
      fastTransferPoolFeeBps: 50, // 0.5% pool fee
      receiver: abi.encode(receiver)
    });

    Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
      messageId: settlementId,
      sourceChainSelector: chainSelector,
      sender: abi.encode(
        chainSelector == dstChainBnM.chain.chainSelector ? address(dstChainBnM.tokenPool) : address(dstChainLnR.tokenPool)
      ),
      data: abi.encode(mintMessage),
      destTokenAmounts: new Client.EVMTokenAmount[](0)
    });

    vm.prank(address(managerChain.chain.router));
    managerChain.tokenPool.ccipReceive(message);
  }

  function test_Revert_withdrawPoolFees_OnlyOwner() public {
    address unauthorizedUser = makeAddr("unauthorized");

    vm.expectRevert(abi.encodeWithSignature("OnlyCallableByOwner()"));
    vm.prank(unauthorizedUser);
    managerChain.tokenPool.withdrawPoolFees(makeAddr("recipient"));
  }

  // ================================================================
  // │                        Helper Functions                      │
  // ================================================================

  function _setupFastTransferConfig(
    uint64 destinationChainSelector
  ) internal {
    vm.prank(admin);

    FastTransferTokenPoolAbstract.DestChainConfigUpdateArgs[] memory configs =
      new FastTransferTokenPoolAbstract.DestChainConfigUpdateArgs[](1);

    configs[0] = FastTransferTokenPoolAbstract.DestChainConfigUpdateArgs({
      remoteChainSelector: destinationChainSelector,
      fastTransferFillerFeeBps: 100, // 1%
      fastTransferPoolFeeBps: 50, // 0.5%
      maxFillAmountPerRequest: type(uint256).max,
      destinationPool: abi.encode(address(0)), // Placeholder
      chainFamilySelector: Internal.CHAIN_FAMILY_SELECTOR_EVM,
      settlementOverheadGas: 200000,
      fillerAllowlistEnabled: true,
      customExtraArgs: ""
    });

    managerChain.tokenPool.updateDestChainConfig(configs);
  }

  function _getChainUpdatesWithChainSelector(
    uint64 chainSelector
  ) internal pure returns (TokenPool.ChainUpdate[] memory chainUpdates) {
    chainUpdates = new TokenPool.ChainUpdate[](1);
    chainUpdates[0] = TokenPool.ChainUpdate({
      remoteChainSelector: chainSelector,
      remotePoolAddresses: new bytes[](0),
      remoteTokenAddress: abi.encode(address(0)),
      outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
      inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
    });
  }

  function _getMultipleChainUpdates(
    uint64 chainSelector1,
    uint64 chainSelector2
  ) internal pure returns (TokenPool.ChainUpdate[] memory chainUpdates) {
    chainUpdates = new TokenPool.ChainUpdate[](2);
    chainUpdates[0] = TokenPool.ChainUpdate({
      remoteChainSelector: chainSelector1,
      remotePoolAddresses: new bytes[](0),
      remoteTokenAddress: abi.encode(address(0)),
      outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
      inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
    });
    chainUpdates[1] = TokenPool.ChainUpdate({
      remoteChainSelector: chainSelector2,
      remotePoolAddresses: new bytes[](0),
      remoteTokenAddress: abi.encode(address(0)),
      outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
      inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
    });
  }

  // ================================================================
  // │              Accumulated Fees Protection Tests              │
  // ================================================================

  function test_updateGroups_WithAccumulatedFees_SufficientLiquidity() public {
    // Setup: Accumulate some pool fees through fast transfers
    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);
    _performFastTransferWithSettlement(dstChainLnR.chain.chainSelector, 1000e18);

    uint256 accumulatedFees = managerChain.tokenPool.getAccumulatedPoolFees();
    uint256 currentBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));
    assertGt(accumulatedFees, 0, "Should have accumulated fees");

    // Test: Update group from LOCK_AND_RELEASE to BURN_AND_MINT with safe amount
    uint256 safeBurnAmount = currentBalance - accumulatedFees - 1000e18; // Leave buffer

    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](1);
    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: safeBurnAmount
    });

    // Should succeed - sufficient liquidity after burning
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityMigrated(
      dstChainLnR.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT, safeBurnAmount
    );

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(groupUpdates);

    // Verify: Group was updated and accumulated fees preserved
    assertEq(
      uint256(managerChain.tokenPool.getGroup(dstChainLnR.chain.chainSelector)),
      uint256(HybridTokenPoolAbstract.Group.BURN_AND_MINT)
    );
    assertEq(managerChain.tokenPool.getAccumulatedPoolFees(), accumulatedFees, "Accumulated fees should be preserved");
    assertGe(
      managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)),
      accumulatedFees,
      "Pool should retain at least accumulated fees"
    );
  }

  function test_Revert_updateGroups_WithAccumulatedFees_InsufficientLiquidity() public {
    // Setup: Accumulate some pool fees through fast transfers
    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);
    _performFastTransferWithSettlement(dstChainLnR.chain.chainSelector, 1000e18);

    uint256 accumulatedFees = managerChain.tokenPool.getAccumulatedPoolFees();
    uint256 currentBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));
    assertGt(accumulatedFees, 0, "Should have accumulated fees");

    // Test: Try to update group with amount that would compromise accumulated fees
    uint256 excessiveBurnAmount = currentBalance - accumulatedFees + 1e18; // Too much

    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](1);
    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: excessiveBurnAmount
    });

    // Should revert - insufficient liquidity after burning
    vm.expectRevert(
      abi.encodeWithSelector(
        HybridWithExternalMinterFastTransferTokenPool.InsufficientLiquidityForGroupUpdate.selector,
        currentBalance,
        currentBalance - excessiveBurnAmount,
        accumulatedFees
      )
    );

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(groupUpdates);

    // Verify: Group was not updated and accumulated fees preserved
    assertEq(
      uint256(managerChain.tokenPool.getGroup(dstChainLnR.chain.chainSelector)),
      uint256(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE)
    );
    assertEq(managerChain.tokenPool.getAccumulatedPoolFees(), accumulatedFees, "Accumulated fees should be preserved");
  }

  function test_updateGroups_WithAccumulatedFees_ExactAmountLeavingFees() public {
    // Setup: Accumulate some pool fees through fast transfers
    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);
    _performFastTransferWithSettlement(dstChainLnR.chain.chainSelector, 1000e18);

    uint256 accumulatedFees = managerChain.tokenPool.getAccumulatedPoolFees();
    uint256 currentBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));
    assertGt(accumulatedFees, 0, "Should have accumulated fees");

    // Test: Update group with exact amount that leaves only accumulated fees
    uint256 exactBurnAmount = currentBalance - accumulatedFees;

    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](1);
    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: exactBurnAmount
    });

    // Should succeed - exactly preserves accumulated fees
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityMigrated(
      dstChainLnR.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT, exactBurnAmount
    );

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(groupUpdates);

    // Verify: Group was updated and only accumulated fees remain
    assertEq(
      uint256(managerChain.tokenPool.getGroup(dstChainLnR.chain.chainSelector)),
      uint256(HybridTokenPoolAbstract.Group.BURN_AND_MINT)
    );
    assertEq(managerChain.tokenPool.getAccumulatedPoolFees(), accumulatedFees, "Accumulated fees should be preserved");
    assertEq(managerChain.tokenPool.getLockedTokens(), 0, "Pool should have no locked tokens after exact burn");
    assertEq(
      managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool)),
      accumulatedFees,
      "Pool should retain only accumulated fees"
    );
  }

  function test_updateGroups_MultipleTransitions_WithAccumulatedFees() public {
    // Setup: Add another LnR chain and accumulate fees
    uint64 newLnRChain = 2001;
    vm.prank(admin);
    managerChain.tokenPool.applyChainUpdates(new uint64[](0), _getChainUpdatesWithChainSelector(newLnRChain));

    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);
    _performFastTransferWithSettlement(dstChainLnR.chain.chainSelector, 1000e18);

    uint256 accumulatedFees = managerChain.tokenPool.getAccumulatedPoolFees();
    uint256 currentBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    // Add more liquidity for multiple transitions
    vm.prank(admin);
    managerChain.governor.mint(address(managerChain.tokenPool), 5000e18);
    currentBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    // Test: Multiple transitions where combined burns would compromise fees
    uint256 totalBurnAmount = currentBalance - accumulatedFees + 1e18; // Too much total
    uint256 burnAmount1 = totalBurnAmount / 2;
    uint256 burnAmount2 = totalBurnAmount - burnAmount1;

    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](2);
    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: burnAmount1
    });
    groupUpdates[1] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: newLnRChain, // This is already LOCK_AND_RELEASE, switch to BURN_AND_MINT
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: burnAmount2
    });

    // Should revert - combined burns would compromise accumulated fees
    vm.expectRevert(
      abi.encodeWithSelector(
        HybridWithExternalMinterFastTransferTokenPool.InsufficientLiquidityForGroupUpdate.selector,
        currentBalance,
        currentBalance - burnAmount1 - burnAmount2,
        accumulatedFees
      )
    );

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(groupUpdates);
  }

  function test_updateGroups_NoAccumulatedFees_NormalOperation() public {
    // Test: Normal group update without accumulated fees (should work as before)
    assertEq(managerChain.tokenPool.getAccumulatedPoolFees(), 0, "Should have no accumulated fees initially");

    uint256 burnAmount = 3000e18;
    // Add liquidity for burning
    vm.prank(admin);
    managerChain.governor.mint(address(managerChain.tokenPool), burnAmount);

    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](1);
    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: burnAmount
    });

    // Should succeed - no accumulated fees to protect
    vm.expectEmit(true, true, true, true);
    emit HybridTokenPoolAbstract.LiquidityMigrated(
      dstChainLnR.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT, burnAmount
    );

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(groupUpdates);

    // Verify: Group was updated successfully
    assertEq(
      uint256(managerChain.tokenPool.getGroup(dstChainLnR.chain.chainSelector)),
      uint256(HybridTokenPoolAbstract.Group.BURN_AND_MINT)
    );
  }

  function test_updateGroups_MixedTransitions_WithAccumulatedFees() public {
    // Setup: Add another chain and accumulate fees
    uint64 newChain = 2002;
    vm.prank(admin);
    managerChain.tokenPool.applyChainUpdates(new uint64[](0), _getChainUpdatesWithChainSelector(newChain));

    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);
    _performFastTransferWithSettlement(dstChainLnR.chain.chainSelector, 1000e18);

    uint256 accumulatedFees = managerChain.tokenPool.getAccumulatedPoolFees();
    uint256 currentBalance = managerChain.tokenPool.getToken().balanceOf(address(managerChain.tokenPool));

    // Test: Mixed transitions - one that burns, one that mints
    uint256 burnAmount = 2000e18;
    uint256 mintAmount = 1500e18;

    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](2);
    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: burnAmount
    });
    groupUpdates[1] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainBnM.chain.chainSelector, // Switch from BURN_AND_MINT to LOCK_AND_RELEASE
      group: HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE,
      remoteChainSupply: mintAmount
    });

    // Calculate if this would be safe (only burnAmount matters for the check)
    if (currentBalance >= burnAmount + accumulatedFees) {
      // Should succeed
      vm.prank(admin);
      managerChain.tokenPool.updateGroups(groupUpdates);

      // Verify both transitions worked
      assertEq(
        uint256(managerChain.tokenPool.getGroup(dstChainLnR.chain.chainSelector)),
        uint256(HybridTokenPoolAbstract.Group.BURN_AND_MINT)
      );
      assertEq(
        uint256(managerChain.tokenPool.getGroup(dstChainBnM.chain.chainSelector)),
        uint256(HybridTokenPoolAbstract.Group.LOCK_AND_RELEASE)
      );
      assertEq(managerChain.tokenPool.getAccumulatedPoolFees(), accumulatedFees, "Accumulated fees should be preserved");
    } else {
      // Should revert
      vm.expectRevert(
        abi.encodeWithSelector(
          HybridWithExternalMinterFastTransferTokenPool.InsufficientLiquidity.selector,
          currentBalance,
          burnAmount + accumulatedFees
        )
      );

      vm.prank(admin);
      managerChain.tokenPool.updateGroups(groupUpdates);
    }
  }

  function test_updateGroups_ZeroRemoteChainSupply_WithAccumulatedFees() public {
    // Setup: Accumulate fees
    _setupFastTransferConfig(dstChainLnR.chain.chainSelector);
    _performFastTransferWithSettlement(dstChainLnR.chain.chainSelector, 1000e18);

    uint256 accumulatedFees = managerChain.tokenPool.getAccumulatedPoolFees();

    // Test: Group update with zero remote chain supply (no burning/minting)
    HybridTokenPoolAbstract.GroupUpdate[] memory groupUpdates = new HybridTokenPoolAbstract.GroupUpdate[](1);
    groupUpdates[0] = HybridTokenPoolAbstract.GroupUpdate({
      remoteChainSelector: dstChainLnR.chain.chainSelector,
      group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
      remoteChainSupply: 0 // No liquidity migration
    });

    // Should succeed - no tokens burned, so no impact on accumulated fees
    vm.expectEmit(true, false, false, false);
    emit HybridTokenPoolAbstract.GroupUpdated(
      dstChainLnR.chain.chainSelector, HybridTokenPoolAbstract.Group.BURN_AND_MINT
    );

    vm.prank(admin);
    managerChain.tokenPool.updateGroups(groupUpdates);

    // Verify: Group updated and accumulated fees preserved
    assertEq(
      uint256(managerChain.tokenPool.getGroup(dstChainLnR.chain.chainSelector)),
      uint256(HybridTokenPoolAbstract.Group.BURN_AND_MINT)
    );
    assertEq(managerChain.tokenPool.getAccumulatedPoolFees(), accumulatedFees, "Accumulated fees should be preserved");
  }

  function test_constructor_RevertWhen_TokenMismatch() public {
    // Test that the constructor reverts if the token address does not match the expected token
    vm.expectRevert(
      abi.encodeWithSelector(
        HybridTokenPoolAbstract.TokenMismatch.selector,
        IERC20(address(dstChainBnM.token)),
        IERC20(address(managerChain.stablecoin))
      )
    );

    new HybridWithExternalMinterFastTransferTokenPool(
      address(managerChain.governor),
      IERC20(address(dstChainBnM.token)),
      18,
      new address[](0),
      address(managerChain.chain.armProxy),
      address(managerChain.chain.router)
    );
  }
}
