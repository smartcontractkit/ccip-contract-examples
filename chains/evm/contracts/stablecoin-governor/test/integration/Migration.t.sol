// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../Utils.t.sol";

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";

import {IERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
  ProxyAdmin,
  TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {TokenGovernor} from "../../../stablecoin-governor/TokenGovernor.sol";
import {BurnMintWithExternalMinterTokenPool} from "../../BurnMintWithExternalMinterTokenPool.sol";
import "../../HybridTokenPoolAbstract.sol";
import "../../HybridWithExternalMinterTokenPool.sol";
import "../../checkers/CheckerCounter.sol";
import {Stablecoin} from "../utils/Stablecoin.sol";

contract MigrationTest is Utils {
  struct ChainParams {
    CCIPChain chain;
    address tokenPool;
    address multisig;
    TokenGovernor governor;
    CheckerCounter checker;
    Stablecoin stablecoin;
  }

  ChainParams managerChain1;
  ChainParams nativeChain2;
  ChainParams nativeChain3;
  ChainParams lnrChain4;
  ChainParams lnrChain5;
  ChainParams lnrChain6;

  function setUp() public {
    _addChains(6);
    _wireAll();

    managerChain1.chain = chains[0];
    nativeChain2.chain = chains[1];
    nativeChain3.chain = chains[2];
    lnrChain4.chain = chains[3];
    lnrChain5.chain = chains[4];
    lnrChain6.chain = chains[5];

    vm.startPrank(admin);

    // Manager chain1
    {
      managerChain1.stablecoin = Stablecoin(
        address(
          new TransparentUpgradeableProxy(
            address(new Stablecoin()),
            admin,
            abi.encodeWithSelector(Stablecoin.initialize.selector, "Stablecoin", "STABLE")
          )
        )
      );
      managerChain1.governor = new TokenGovernor(address(managerChain1.stablecoin), 0, admin);
      managerChain1.checker = new CheckerCounter(address(managerChain1.governor));

      managerChain1.tokenPool = address(
        new HybridWithExternalMinterTokenPool(
          address(managerChain1.governor),
          IERC20(address(managerChain1.stablecoin)),
          18,
          new address[](0),
          address(managerChain1.chain.armProxy),
          address(managerChain1.chain.router)
        )
      );

      managerChain1.stablecoin.transferOwnership(address(managerChain1.governor));
      managerChain1.governor.acceptOwnership();

      managerChain1.governor.grantRole(managerChain1.governor.BRIDGE_MINTER_OR_BURNER_ROLE(), managerChain1.tokenPool);
      managerChain1.governor.grantRole(managerChain1.governor.CHECKER_ADMIN_ROLE(), admin);
      managerChain1.governor.setChecker(address(managerChain1.checker));

      HybridWithExternalMinterTokenPool(managerChain1.tokenPool).setRebalancer(admin);

      managerChain1.chain.tokenAdminRegistry.proposeAdministrator(address(managerChain1.stablecoin), admin);
      managerChain1.chain.tokenAdminRegistry.acceptAdminRole(address(managerChain1.stablecoin));
      managerChain1.chain.tokenAdminRegistry.setPool(address(managerChain1.stablecoin), managerChain1.tokenPool);
    }

    // Native chain2
    {
      nativeChain2.stablecoin = Stablecoin(
        address(
          new TransparentUpgradeableProxy(
            address(new Stablecoin()),
            admin,
            abi.encodeWithSelector(Stablecoin.initialize.selector, "Stablecoin", "STABLE")
          )
        )
      );
      nativeChain2.governor = new TokenGovernor(address(nativeChain2.stablecoin), 0, admin);
      nativeChain2.checker = new CheckerCounter(address(nativeChain2.governor));

      nativeChain2.tokenPool = address(
        new BurnMintWithExternalMinterTokenPool(
          address(nativeChain2.governor),
          IERC20(IExternalMinter(address(nativeChain2.governor)).getToken()),
          18,
          new address[](0),
          address(nativeChain2.chain.armProxy),
          address(nativeChain2.chain.router)
        )
      );

      nativeChain2.stablecoin.transferOwnership(address(nativeChain2.governor));
      nativeChain2.governor.acceptOwnership();

      nativeChain2.governor.grantRole(nativeChain2.governor.BRIDGE_MINTER_OR_BURNER_ROLE(), nativeChain2.tokenPool);
      nativeChain2.governor.grantRole(nativeChain2.governor.CHECKER_ADMIN_ROLE(), admin);
      nativeChain2.governor.setChecker(address(nativeChain2.checker));

      nativeChain2.chain.tokenAdminRegistry.proposeAdministrator(address(nativeChain2.stablecoin), admin);
      nativeChain2.chain.tokenAdminRegistry.acceptAdminRole(address(nativeChain2.stablecoin));
      nativeChain2.chain.tokenAdminRegistry.setPool(address(nativeChain2.stablecoin), nativeChain2.tokenPool);
    }

    // Native chain3
    {
      nativeChain3.stablecoin = Stablecoin(
        address(
          new TransparentUpgradeableProxy(
            address(new Stablecoin()),
            admin,
            abi.encodeWithSelector(Stablecoin.initialize.selector, "Stablecoin", "STABLE")
          )
        )
      );
      nativeChain3.governor = new TokenGovernor(address(nativeChain3.stablecoin), 0, admin);
      nativeChain3.checker = new CheckerCounter(address(nativeChain3.governor));

      nativeChain3.tokenPool = address(
        new BurnMintWithExternalMinterTokenPool(
          address(nativeChain3.governor),
          IERC20(IExternalMinter(address(nativeChain3.governor)).getToken()),
          18,
          new address[](0),
          address(nativeChain3.chain.armProxy),
          address(nativeChain3.chain.router)
        )
      );

      nativeChain3.stablecoin.transferOwnership(address(nativeChain3.governor));
      nativeChain3.governor.acceptOwnership();

      nativeChain3.governor.grantRole(nativeChain3.governor.BRIDGE_MINTER_OR_BURNER_ROLE(), nativeChain3.tokenPool);
      nativeChain3.governor.grantRole(nativeChain3.governor.CHECKER_ADMIN_ROLE(), admin);
      nativeChain3.governor.setChecker(address(nativeChain3.checker));

      nativeChain3.chain.tokenAdminRegistry.proposeAdministrator(address(nativeChain3.stablecoin), admin);
      nativeChain3.chain.tokenAdminRegistry.acceptAdminRole(address(nativeChain3.stablecoin));
      nativeChain3.chain.tokenAdminRegistry.setPool(address(nativeChain3.stablecoin), nativeChain3.tokenPool);
    }

    // LnR chain4
    {
      lnrChain4.stablecoin = Stablecoin(
        address(
          new TransparentUpgradeableProxy(
            address(new Stablecoin()),
            admin,
            abi.encodeWithSelector(Stablecoin.initialize.selector, "Stablecoin", "STABLE")
          )
        )
      );
      lnrChain4.governor = new TokenGovernor(address(lnrChain4.stablecoin), 0, admin);

      lnrChain4.tokenPool = address(
        new BurnMintWithExternalMinterTokenPool(
          address(lnrChain4.governor),
          IERC20(IExternalMinter(address(lnrChain4.governor)).getToken()),
          18,
          new address[](0),
          address(lnrChain4.chain.armProxy),
          address(lnrChain4.chain.router)
        )
      );

      lnrChain4.stablecoin.transferOwnership(address(lnrChain4.governor));
      lnrChain4.governor.acceptOwnership();

      lnrChain4.governor.grantRole(lnrChain4.governor.BRIDGE_MINTER_OR_BURNER_ROLE(), lnrChain4.tokenPool);

      lnrChain4.chain.tokenAdminRegistry.proposeAdministrator(address(lnrChain4.stablecoin), admin);
      lnrChain4.chain.tokenAdminRegistry.acceptAdminRole(address(lnrChain4.stablecoin));
      lnrChain4.chain.tokenAdminRegistry.setPool(address(lnrChain4.stablecoin), lnrChain4.tokenPool);
    }

    // LnR chain5
    {
      lnrChain5.stablecoin = Stablecoin(
        address(
          new TransparentUpgradeableProxy(
            address(new Stablecoin()),
            admin,
            abi.encodeWithSelector(Stablecoin.initialize.selector, "Stablecoin", "STABLE")
          )
        )
      );
      lnrChain5.governor = new TokenGovernor(address(lnrChain5.stablecoin), 0, admin);

      lnrChain5.tokenPool = address(
        new BurnMintWithExternalMinterTokenPool(
          address(lnrChain5.governor),
          IERC20(IExternalMinter(address(lnrChain5.governor)).getToken()),
          18,
          new address[](0),
          address(lnrChain5.chain.armProxy),
          address(lnrChain5.chain.router)
        )
      );

      lnrChain5.stablecoin.transferOwnership(address(lnrChain5.governor));
      lnrChain5.governor.acceptOwnership();

      lnrChain5.governor.grantRole(lnrChain5.governor.BRIDGE_MINTER_OR_BURNER_ROLE(), lnrChain5.tokenPool);

      lnrChain5.chain.tokenAdminRegistry.proposeAdministrator(address(lnrChain5.stablecoin), admin);
      lnrChain5.chain.tokenAdminRegistry.acceptAdminRole(address(lnrChain5.stablecoin));
      lnrChain5.chain.tokenAdminRegistry.setPool(address(lnrChain5.stablecoin), lnrChain5.tokenPool);
    }

    // LnR chain6
    {
      lnrChain6.stablecoin = Stablecoin(
        address(
          new TransparentUpgradeableProxy(
            address(new Stablecoin()),
            admin,
            abi.encodeWithSelector(Stablecoin.initialize.selector, "Stablecoin", "STABLE")
          )
        )
      );
      lnrChain6.governor = new TokenGovernor(address(lnrChain6.stablecoin), 0, admin);

      lnrChain6.tokenPool = address(
        new BurnMintWithExternalMinterTokenPool(
          address(lnrChain6.governor),
          IERC20(IExternalMinter(address(lnrChain6.governor)).getToken()),
          18,
          new address[](0),
          address(lnrChain6.chain.armProxy),
          address(lnrChain6.chain.router)
        )
      );

      lnrChain6.stablecoin.transferOwnership(address(lnrChain6.governor));
      lnrChain6.governor.acceptOwnership();

      lnrChain6.governor.grantRole(lnrChain6.governor.BRIDGE_MINTER_OR_BURNER_ROLE(), lnrChain6.tokenPool);

      lnrChain6.chain.tokenAdminRegistry.proposeAdministrator(address(lnrChain6.stablecoin), admin);
      lnrChain6.chain.tokenAdminRegistry.acceptAdminRole(address(lnrChain6.stablecoin));
      lnrChain6.chain.tokenAdminRegistry.setPool(address(lnrChain6.stablecoin), lnrChain6.tokenPool);
    }

    vm.stopPrank();

    // Link manager with all chains
    {
      _linkTokenPools(
        managerChain1.chain.chainSelector,
        managerChain1.tokenPool,
        nativeChain2.chain.chainSelector,
        nativeChain2.tokenPool
      );
      _linkTokenPools(
        managerChain1.chain.chainSelector,
        managerChain1.tokenPool,
        nativeChain3.chain.chainSelector,
        nativeChain3.tokenPool
      );
      _linkTokenPools(
        managerChain1.chain.chainSelector, managerChain1.tokenPool, lnrChain4.chain.chainSelector, lnrChain4.tokenPool
      );
      _linkTokenPools(
        managerChain1.chain.chainSelector, managerChain1.tokenPool, lnrChain5.chain.chainSelector, lnrChain5.tokenPool
      );
      _linkTokenPools(
        managerChain1.chain.chainSelector, managerChain1.tokenPool, lnrChain6.chain.chainSelector, lnrChain6.tokenPool
      );
    }

    // Link native chains
    {
      _linkTokenPools(
        nativeChain2.chain.chainSelector,
        nativeChain2.tokenPool,
        nativeChain3.chain.chainSelector,
        nativeChain3.tokenPool
      );
    }

    // Link LnR chains
    {
      _linkTokenPools(
        lnrChain4.chain.chainSelector, lnrChain4.tokenPool, lnrChain5.chain.chainSelector, lnrChain5.tokenPool
      );
      _linkTokenPools(
        lnrChain4.chain.chainSelector, lnrChain4.tokenPool, lnrChain6.chain.chainSelector, lnrChain6.tokenPool
      );
      _linkTokenPools(
        lnrChain5.chain.chainSelector, lnrChain5.tokenPool, lnrChain6.chain.chainSelector, lnrChain6.tokenPool
      );
    }

    // Update groups
    {
      HybridTokenPoolAbstract.GroupUpdate[] memory updates = new HybridTokenPoolAbstract.GroupUpdate[](2);
      updates[0] = HybridTokenPoolAbstract.GroupUpdate({
        remoteChainSelector: nativeChain2.chain.chainSelector,
        group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
        remoteChainSupply: 0
      });
      updates[1] = HybridTokenPoolAbstract.GroupUpdate({
        remoteChainSelector: nativeChain3.chain.chainSelector,
        group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
        remoteChainSupply: 0
      });

      vm.prank(admin);
      HybridWithExternalMinterTokenPool(managerChain1.tokenPool).updateGroups(updates);
    }

    vm.label(address(managerChain1.stablecoin), "STABLE_1");
    vm.label(managerChain1.tokenPool, "TokenPool_1");
    vm.label(address(managerChain1.governor), "Governor_1");
    vm.label(address(managerChain1.checker), "Checker_1");

    vm.label(address(nativeChain2.stablecoin), "STABLE_2");
    vm.label(nativeChain2.tokenPool, "TokenPool_2");
    vm.label(address(nativeChain2.governor), "Governor_2");
    vm.label(address(nativeChain2.checker), "Checker_2");

    vm.label(address(nativeChain3.stablecoin), "STABLE_3");
    vm.label(nativeChain3.tokenPool, "TokenPool_3");
    vm.label(address(nativeChain3.governor), "Governor_3");
    vm.label(address(nativeChain3.checker), "Checker_3");

    vm.label(address(lnrChain4.stablecoin), "STABLE_4");
    vm.label(lnrChain4.tokenPool, "TokenPool_4");

    vm.label(address(lnrChain5.stablecoin), "STABLE_5");
    vm.label(lnrChain5.tokenPool, "TokenPool_5");

    vm.label(address(lnrChain6.stablecoin), "STABLE_6");
    vm.label(lnrChain6.tokenPool, "TokenPool_6");

    vm.deal(alice, 1e18);
    vm.deal(bob, 1e18);

    // Mint Alice some stablecoins
    vm.startPrank(admin);
    {
      managerChain1.governor.grantRole(managerChain1.governor.MINTER_ROLE(), admin);
      managerChain1.governor.mint(alice, 1e18);

      nativeChain2.governor.grantRole(nativeChain2.governor.MINTER_ROLE(), admin);
      nativeChain2.governor.mint(alice, 2e18);

      nativeChain3.governor.grantRole(nativeChain3.governor.MINTER_ROLE(), admin);
      nativeChain3.governor.mint(alice, 3e18);

      lnrChain4.governor.grantRole(lnrChain4.governor.MINTER_ROLE(), admin);
      lnrChain4.governor.mint(alice, 4e18);

      lnrChain5.governor.grantRole(lnrChain5.governor.MINTER_ROLE(), admin);
      lnrChain5.governor.mint(alice, 5e18);

      lnrChain6.governor.grantRole(lnrChain6.governor.MINTER_ROLE(), admin);
      lnrChain6.governor.mint(alice, 6e18);
    }

    // As Alice has 4+5+6=15 tokens on Lock and Release chains, the manager has to have at least 15 tokens
    {
      vm.startPrank(admin);
      managerChain1.governor.mint(admin, 15e18);
      managerChain1.stablecoin.approve(managerChain1.tokenPool, 15e18);
      HybridWithExternalMinterTokenPool(managerChain1.tokenPool).provideLiquidity(15e18);
      vm.stopPrank();
    }
  }

  function test_migrationChain4() public {
    // Create in-flight messages to chain 4
    MessageReceipt memory inflight1to4 = _sendMessage(managerChain1, lnrChain4, alice, bob, 0.1e18);
    MessageReceipt memory inflight5to4 = _sendMessage(lnrChain5, lnrChain4, alice, bob, 0.2e18);
    MessageReceipt memory inflight6to4 = _sendMessage(lnrChain6, lnrChain4, alice, bob, 0.3e18);

    RateLimiter.Config memory pausedConfig = RateLimiter.Config({isEnabled: true, capacity: 2, rate: 1});
    RateLimiter.Config memory defaultConfig = RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18});

    /* (1) Pause bridge messages from/to chain 4 */

    vm.startPrank(admin);
    // Pause messages from chain 4
    {
      TokenPool(lnrChain4.tokenPool).setChainRateLimiterConfig(
        managerChain1.chain.chainSelector, pausedConfig, defaultConfig
      );
      TokenPool(lnrChain4.tokenPool).setChainRateLimiterConfig(
        lnrChain5.chain.chainSelector, pausedConfig, defaultConfig
      );
      TokenPool(lnrChain4.tokenPool).setChainRateLimiterConfig(
        lnrChain6.chain.chainSelector, pausedConfig, defaultConfig
      );
    }

    // Pause messages to chain 4
    {
      TokenPool(managerChain1.tokenPool).setChainRateLimiterConfig(
        lnrChain4.chain.chainSelector, pausedConfig, defaultConfig
      );
      TokenPool(lnrChain5.tokenPool).setChainRateLimiterConfig(
        lnrChain4.chain.chainSelector, pausedConfig, defaultConfig
      );
      TokenPool(lnrChain6.tokenPool).setChainRateLimiterConfig(
        lnrChain4.chain.chainSelector, pausedConfig, defaultConfig
      );
    }
    vm.stopPrank();

    // Make sure no one can send messages from chain 4
    {
      bytes memory e =
        abi.encodeWithSelector(RateLimiter.TokenMaxCapacityExceeded.selector, pausedConfig.capacity, 0.1e18);

      _sendMessage(lnrChain4, managerChain1, alice, bob, 0.1e18, bytes.concat(e, abi.encode(lnrChain4.stablecoin)));
      _sendMessage(lnrChain4, lnrChain5, alice, bob, 0.1e18, bytes.concat(e, abi.encode(lnrChain4.stablecoin)));
      _sendMessage(lnrChain4, lnrChain6, alice, bob, 0.1e18, bytes.concat(e, abi.encode(lnrChain4.stablecoin)));
    }

    // Make sure no one can send messages to chain 4
    {
      bytes memory e =
        abi.encodeWithSelector(RateLimiter.TokenMaxCapacityExceeded.selector, pausedConfig.capacity, 0.1e18);

      _sendMessage(managerChain1, lnrChain4, alice, bob, 0.1e18, bytes.concat(e, abi.encode(managerChain1.stablecoin)));
      _sendMessage(lnrChain5, lnrChain4, alice, bob, 0.1e18, bytes.concat(e, abi.encode(lnrChain5.stablecoin)));
      _sendMessage(lnrChain6, lnrChain4, alice, bob, 0.1e18, bytes.concat(e, abi.encode(lnrChain6.stablecoin)));
    }

    /* (2) Resolve in-flight messages */

    _receiveMessage(managerChain1, lnrChain4, inflight1to4);
    _receiveMessage(lnrChain5, lnrChain4, inflight5to4);
    _receiveMessage(lnrChain6, lnrChain4, inflight6to4);

    assertEq(managerChain1.stablecoin.balanceOf(alice), 0.9e18, "test_migrationChain4::1");
    assertEq(managerChain1.stablecoin.balanceOf(managerChain1.tokenPool), 15.1e18, "test_migrationChain4::2");
    assertEq(lnrChain5.stablecoin.balanceOf(alice), 4.8e18, "test_migrationChain4::3");
    assertEq(lnrChain6.stablecoin.balanceOf(alice), 5.7e18, "test_migrationChain4::4");

    assertEq(lnrChain4.stablecoin.balanceOf(bob), 0.1e18 + 0.2e18 + 0.3e18, "test_migrationChain4::5");

    /* (3) Deploy new Governor and transfer token ownership */

    {
      lnrChain4.multisig = makeAddr("multisig4");

      TokenGovernor newGovernor = new TokenGovernor(address(lnrChain4.stablecoin), 0, lnrChain4.multisig);

      newGovernor.renounceRole(newGovernor.DEFAULT_ADMIN_ROLE(), address(this));

      vm.prank(admin);
      lnrChain4.governor.transferOwnership(address(newGovernor));

      vm.prank(lnrChain4.multisig);
      newGovernor.acceptOwnership();

      lnrChain4.governor = newGovernor;
    }

    /* (4) Transfer token ProxyAdmin and TokenAdminRegistry ownership */

    {
      address proxyAdmin = address(uint160(uint256(vm.load(address(lnrChain4.stablecoin), ERC1967Utils.ADMIN_SLOT))));

      vm.startPrank(admin);
      ProxyAdmin(proxyAdmin).transferOwnership(lnrChain4.multisig);

      lnrChain4.chain.tokenAdminRegistry.transferAdminRole(address(lnrChain4.stablecoin), lnrChain4.multisig);
      vm.stopPrank();

      vm.prank(lnrChain4.multisig);
      lnrChain4.chain.tokenAdminRegistry.acceptAdminRole(address(lnrChain4.stablecoin));
    }

    /* (5) Deploy and configure new TokenPool */

    {
      address newTokenPool = address(
        new BurnMintWithExternalMinterTokenPool(
          address(lnrChain4.governor),
          IERC20(IExternalMinter(address(lnrChain4.governor)).getToken()),
          18,
          new address[](0),
          address(lnrChain4.chain.armProxy),
          address(lnrChain4.chain.router)
        )
      );

      TokenPool(newTokenPool).transferOwnership(lnrChain4.multisig);

      vm.startPrank(lnrChain4.multisig);
      TokenPool(newTokenPool).acceptOwnership();

      // Link new TokenPool to manager and native chains
      {
        bytes[] memory manager1PoolAddresses = new bytes[](1);
        bytes[] memory native2PoolAddresses = new bytes[](1);
        bytes[] memory native3PoolAddresses = new bytes[](1);

        manager1PoolAddresses[0] = abi.encode(managerChain1.tokenPool);
        native2PoolAddresses[0] = abi.encode(nativeChain2.tokenPool);
        native3PoolAddresses[0] = abi.encode(nativeChain3.tokenPool);

        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](3);
        chainUpdates[0] = TokenPool.ChainUpdate({
          remoteChainSelector: managerChain1.chain.chainSelector,
          remotePoolAddresses: manager1PoolAddresses,
          remoteTokenAddress: abi.encode(managerChain1.stablecoin),
          outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18}),
          inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18})
        });
        chainUpdates[1] = TokenPool.ChainUpdate({
          remoteChainSelector: nativeChain2.chain.chainSelector,
          remotePoolAddresses: native2PoolAddresses,
          remoteTokenAddress: abi.encode(nativeChain2.stablecoin),
          outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18}),
          inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18})
        });
        chainUpdates[2] = TokenPool.ChainUpdate({
          remoteChainSelector: nativeChain3.chain.chainSelector,
          remotePoolAddresses: native3PoolAddresses,
          remoteTokenAddress: abi.encode(nativeChain3.stablecoin),
          outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18}),
          inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18})
        });

        TokenPool(newTokenPool).applyChainUpdates(new uint64[](0), chainUpdates);
      }
      vm.stopPrank();

      // Link native chains to new TokenPool
      {
        bytes[] memory chain4PoolAddresses = new bytes[](1);
        chain4PoolAddresses[0] = abi.encode(newTokenPool);

        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = TokenPool.ChainUpdate({
          remoteChainSelector: lnrChain4.chain.chainSelector,
          remotePoolAddresses: chain4PoolAddresses,
          remoteTokenAddress: abi.encode(lnrChain4.stablecoin),
          outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18}),
          inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18})
        });

        uint64[] memory removes = new uint64[](1);
        removes[0] = lnrChain4.chain.chainSelector;

        // Remove the chain first to make sure that all previous pools were removed
        vm.prank(admin);
        TokenPool(managerChain1.tokenPool).applyChainUpdates(removes, chainUpdates);

        vm.prank(admin);
        TokenPool(nativeChain2.tokenPool).applyChainUpdates(new uint64[](0), chainUpdates);

        vm.prank(admin);
        TokenPool(nativeChain3.tokenPool).applyChainUpdates(new uint64[](0), chainUpdates);
      }

      lnrChain4.tokenPool = newTokenPool;
    }

    /* (6) Remove the chain from the LnR group */

    {
      uint64[] memory chainSelectors = new uint64[](1);
      chainSelectors[0] = lnrChain4.chain.chainSelector;

      vm.prank(admin);
      TokenPool(lnrChain5.tokenPool).applyChainUpdates(chainSelectors, new TokenPool.ChainUpdate[](0));

      vm.prank(admin);
      TokenPool(lnrChain6.tokenPool).applyChainUpdates(chainSelectors, new TokenPool.ChainUpdate[](0));
    }

    /* (7) Configure roles and set new checker */

    {
      lnrChain4.checker = new CheckerCounter(address(lnrChain4.governor));

      vm.startPrank(lnrChain4.multisig);
      lnrChain4.governor.grantRole(lnrChain4.governor.BRIDGE_MINTER_OR_BURNER_ROLE(), lnrChain4.tokenPool);

      lnrChain4.governor.grantRole(lnrChain4.governor.CHECKER_ADMIN_ROLE(), lnrChain4.multisig);
      lnrChain4.governor.setChecker(address(lnrChain4.checker));
      vm.stopPrank();
    }

    /* (8) Update the chain4 group */

    {
      HybridTokenPoolAbstract.GroupUpdate[] memory updates = new HybridTokenPoolAbstract.GroupUpdate[](1);
      updates[0] = HybridTokenPoolAbstract.GroupUpdate({
        remoteChainSelector: lnrChain4.chain.chainSelector,
        group: HybridTokenPoolAbstract.Group.BURN_AND_MINT,
        remoteChainSupply: lnrChain4.stablecoin.totalSupply()
      });

      vm.prank(admin);
      HybridWithExternalMinterTokenPool(managerChain1.tokenPool).updateGroups(updates);
    }

    assertEq(managerChain1.stablecoin.balanceOf(managerChain1.tokenPool), 15.1e18 - 4.6e18, "test_migrationChain4::6");

    /* (9) Call SetPool on the token registry */
    {
      vm.prank(lnrChain4.multisig);
      lnrChain4.chain.tokenAdminRegistry.setPool(address(lnrChain4.stablecoin), lnrChain4.tokenPool);
    }

    /* (10) Test that messages can be sent from/to chain 4 */

    MessageReceipt memory receipt4to1 = _sendMessage(lnrChain4, managerChain1, alice, bob, 0.1e18);
    _receiveMessage(lnrChain4, managerChain1, receipt4to1);

    MessageReceipt memory receipt4to2 = _sendMessage(lnrChain4, nativeChain2, alice, bob, 0.2e18);
    _receiveMessage(lnrChain4, nativeChain2, receipt4to2);

    MessageReceipt memory receipt4to3 = _sendMessage(lnrChain4, nativeChain3, alice, bob, 0.3e18);
    _receiveMessage(lnrChain4, nativeChain3, receipt4to3);

    MessageReceipt memory receipt1to4 = _sendMessage(managerChain1, lnrChain4, alice, bob, 0.4e18);
    _receiveMessage(managerChain1, lnrChain4, receipt1to4);

    MessageReceipt memory receipt2to4 = _sendMessage(nativeChain2, lnrChain4, alice, bob, 0.5e18);
    _receiveMessage(nativeChain2, lnrChain4, receipt2to4);

    MessageReceipt memory receipt3to4 = _sendMessage(nativeChain3, lnrChain4, alice, bob, 0.6e18);
    _receiveMessage(nativeChain3, lnrChain4, receipt3to4);

    assertEq(managerChain1.stablecoin.balanceOf(alice), 0.9e18 - 0.4e18, "test_migrationChain4::7");
    assertEq(managerChain1.stablecoin.balanceOf(managerChain1.tokenPool), 15.1e18 - 4.6e18, "test_migrationChain4::8");
    assertEq(nativeChain2.stablecoin.balanceOf(alice), 2e18 - 0.5e18, "test_migrationChain4::9");
    assertEq(nativeChain3.stablecoin.balanceOf(alice), 3e18 - 0.6e18, "test_migrationChain4::10");
    assertEq(
      lnrChain4.stablecoin.balanceOf(bob),
      0.1e18 + 0.2e18 + 0.3e18 + 0.4e18 + 0.5e18 + 0.6e18,
      "test_migrationChain4::11"
    );
    assertEq(lnrChain4.stablecoin.balanceOf(alice), 3.4e18, "test_migrationChain4::12");
  }

  struct MessageReceipt {
    address sender;
    address receiver;
    uint256 amount;
    bytes32 id;
  }

  function _sendMessage(
    ChainParams storage src,
    ChainParams storage dst,
    address sender,
    address receiver,
    uint256 amount
  ) internal returns (MessageReceipt memory receipt) {
    return _sendMessage(src, dst, sender, receiver, amount, new bytes(0));
  }

  function _sendMessage(
    ChainParams storage src,
    ChainParams storage dst,
    address sender,
    address receiver,
    uint256 amount,
    bytes memory error
  ) internal returns (MessageReceipt memory receipt) {
    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
    tokenAmounts[0] = Client.EVMTokenAmount({token: address(src.stablecoin), amount: amount});

    Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
      receiver: abi.encode(receiver),
      data: abi.encodePacked(),
      tokenAmounts: tokenAmounts,
      feeToken: address(0),
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 1_000_000, allowOutOfOrderExecution: false}))
    });

    uint256 fee = src.chain.router.getFee(dst.chain.chainSelector, message);

    vm.startPrank(sender);
    src.stablecoin.approve(address(src.chain.router), amount);

    if (error.length > 0) {
      vm.expectRevert(error);
      src.chain.router.ccipSend{value: fee}(dst.chain.chainSelector, message);
    } else {
      bytes32 id = src.chain.router.ccipSend{value: fee}(dst.chain.chainSelector, message);
      receipt = MessageReceipt({sender: sender, receiver: receiver, amount: amount, id: id});
    }
    vm.stopPrank();
  }

  function _receiveMessage(ChainParams storage src, ChainParams storage dst, MessageReceipt memory receipt) internal {
    Internal.Any2EVMTokenTransfer[] memory dstTokenAmounts = new Internal.Any2EVMTokenTransfer[](1);
    dstTokenAmounts[0] = Internal.Any2EVMTokenTransfer({
      sourcePoolAddress: abi.encode(address(src.tokenPool)),
      destTokenAddress: address(dst.stablecoin),
      destGasAmount: 1_000_000,
      extraData: abi.encodePacked(),
      amount: receipt.amount
    });

    Internal.Any2EVMRampMessage memory dstMessage = Internal.Any2EVMRampMessage({
      header: Internal.RampMessageHeader({
        messageId: receipt.id,
        sourceChainSelector: src.chain.chainSelector,
        destChainSelector: dst.chain.chainSelector,
        sequenceNumber: onRamps[dst.chain.chainSelector].getExpectedNextSequenceNumber(src.chain.chainSelector),
        nonce: dst.chain.nonceManager.outboundNonces(src.chain.chainSelector, address(this))
      }),
      sender: abi.encode(receipt.sender),
      data: abi.encodePacked(),
      receiver: receipt.receiver,
      gasLimit: 0,
      tokenAmounts: dstTokenAmounts
    });

    OffRamp offRamp = offRamps[dst.chain.chainSelector];

    vm.prank(address(offRamp));
    offRamp.executeSingleMessage(dstMessage, new bytes[](1), new uint32[](1));
  }
}
