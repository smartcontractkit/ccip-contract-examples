// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IRouter, Router} from "@chainlink/contracts-ccip/contracts/Router.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";
import {IRMNRemote, OffRamp} from "@chainlink/contracts-ccip/contracts/offRamp/OffRamp.sol";
import {OnRamp} from "@chainlink/contracts-ccip/contracts/onRamp/OnRamp.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {TokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";

import {MockArmProxy} from "./mocks/MockArmProxy.sol";
import {MockFeeQuoter} from "./mocks/MockFeeQuoter.sol";
import {MockNonceManager} from "./mocks/MockNonceManager.sol";
import {MockWNative} from "./mocks/MockWNative.sol";

contract Utils is Test {
  struct CCIPChain {
    uint64 chainSelector;
    MockWNative wnative;
    MockArmProxy armProxy;
    Router router;
    TokenAdminRegistry tokenAdminRegistry;
    MockNonceManager nonceManager;
    MockFeeQuoter feeQuoter;
  }

  mapping(uint64 chainSelector => OnRamp onRamp) onRamps;
  mapping(uint64 chainSelector => OffRamp offRamp) offRamps;

  uint64 _chainCounter;

  CCIPChain[] chains;

  address admin = makeAddr("admin");

  address alice = makeAddr("alice");
  address bob = makeAddr("bob");

  function _addChains(
    uint256 nb
  ) internal {
    require(_chainCounter + nb >= 2, "Need at least 2 chains");

    vm.startPrank(admin, admin);

    for (uint256 i = 0; i < nb; i++) {
      CCIPChain storage chain = chains.push();

      uint64 chainSelector = ++_chainCounter;
      chain.chainSelector = chainSelector;

      chain.wnative = new MockWNative();
      chain.armProxy = new MockArmProxy();
      chain.router = new Router(address(chain.wnative), address(chain.armProxy));

      TokenAdminRegistry tokenAdminRegistry = new TokenAdminRegistry();
      tokenAdminRegistry.addRegistryModule(admin);

      chain.tokenAdminRegistry = tokenAdminRegistry;
      chain.nonceManager = new MockNonceManager();
      chain.feeQuoter = new MockFeeQuoter();

      vm.label(address(chain.wnative), string.concat("WNative_", vm.toString(chainSelector)));
      vm.label(address(chain.armProxy), string.concat("ArmProxy_", vm.toString(chainSelector)));
      vm.label(address(chain.router), string.concat("Router_", vm.toString(chainSelector)));
      vm.label(address(chain.tokenAdminRegistry), string.concat("TokenAdminRegistry_", vm.toString(chainSelector)));
      vm.label(address(chain.nonceManager), string.concat("NonceManager_", vm.toString(chainSelector)));
      vm.label(address(chain.feeQuoter), string.concat("FeeQuoter_", vm.toString(chainSelector)));
    }

    vm.stopPrank();
  }

  function _wireAll() internal {
    vm.startPrank(admin, admin);

    uint256 len = chains.length;

    for (uint256 i = 0; i < len; i++) {
      CCIPChain storage srcChain = chains[i];

      OnRamp.StaticConfig memory onRampStaticConfig = OnRamp.StaticConfig({
        chainSelector: srcChain.chainSelector,
        rmnRemote: IRMNRemote(address(srcChain.armProxy)),
        nonceManager: address(srcChain.nonceManager),
        tokenAdminRegistry: address(srcChain.tokenAdminRegistry)
      });
      OnRamp.DynamicConfig memory onRampDynamicConfig = OnRamp.DynamicConfig({
        feeQuoter: address(srcChain.feeQuoter),
        reentrancyGuardEntered: false,
        messageInterceptor: address(0),
        feeAggregator: admin,
        allowlistAdmin: admin
      });

      OnRamp.DestChainConfigArgs[] memory dstChainConfigArgs = new OnRamp.DestChainConfigArgs[](len - 1);
      for (uint256 j = 0; j < len; j++) {
        if (j == i) {
          continue;
        }

        CCIPChain storage dstChain = chains[j];

        dstChainConfigArgs[j < i ? j : j - 1] = OnRamp.DestChainConfigArgs({
          destChainSelector: dstChain.chainSelector,
          router: IRouter(srcChain.router),
          allowlistEnabled: false
        });

        srcChain.feeQuoter.setFee(dstChain.chainSelector, srcChain.chainSelector * 10000 + dstChain.chainSelector);
      }

      OnRamp onRamp = new OnRamp(onRampStaticConfig, onRampDynamicConfig, dstChainConfigArgs);

      onRamps[srcChain.chainSelector] = onRamp;
      vm.label(address(onRamp), string.concat("OnRamp_", vm.toString(srcChain.chainSelector)));
    }

    for (uint256 i = 0; i < len; i++) {
      CCIPChain storage dstChain = chains[i];

      OffRamp.StaticConfig memory offRampStaticConfig = OffRamp.StaticConfig({
        chainSelector: dstChain.chainSelector,
        gasForCallExactCheck: type(uint16).max,
        rmnRemote: IRMNRemote(address(dstChain.armProxy)),
        tokenAdminRegistry: address(dstChain.tokenAdminRegistry),
        nonceManager: address(dstChain.nonceManager)
      });
      OffRamp.DynamicConfig memory offRampDynamicConfig = OffRamp.DynamicConfig({
        feeQuoter: address(dstChain.feeQuoter),
        permissionLessExecutionThresholdSeconds: 60,
        messageInterceptor: address(0)
      });

      OffRamp.SourceChainConfigArgs[] memory sourceChainConfigArgs = new OffRamp.SourceChainConfigArgs[](len - 1);
      for (uint256 j = 0; j < len; j++) {
        if (j == i) {
          continue;
        }

        CCIPChain storage srcChain = chains[j];

        sourceChainConfigArgs[j < i ? j : j - 1] = OffRamp.SourceChainConfigArgs({
          router: IRouter(srcChain.router),
          sourceChainSelector: srcChain.chainSelector,
          isEnabled: true,
          isRMNVerificationDisabled: false,
          onRamp: abi.encode(onRamps[srcChain.chainSelector])
        });
      }

      OffRamp offRamp = new OffRamp(offRampStaticConfig, offRampDynamicConfig, sourceChainConfigArgs);

      offRamps[dstChain.chainSelector] = offRamp;
      vm.label(address(offRamp), string.concat("OffRamp_", vm.toString(dstChain.chainSelector)));
    }

    for (uint256 i = 0; i < len; i++) {
      CCIPChain storage srcChain = chains[i];

      Router.OnRamp[] memory onRamps_ = new Router.OnRamp[](len - 1);
      Router.OffRamp[] memory offRamps_ = new Router.OffRamp[](len - 1);
      for (uint256 j = 0; j < len; j++) {
        if (j == i) {
          continue;
        }

        CCIPChain storage dstChain = chains[j];

        onRamps_[j < i ? j : j - 1] =
          Router.OnRamp({destChainSelector: dstChain.chainSelector, onRamp: address(onRamps[srcChain.chainSelector])});
        offRamps_[j < i ? j : j - 1] = Router.OffRamp({
          sourceChainSelector: dstChain.chainSelector,
          offRamp: address(offRamps[srcChain.chainSelector])
        });
      }

      Router(srcChain.router).applyRampUpdates(onRamps_, new Router.OffRamp[](0), offRamps_);
    }

    vm.stopPrank();
  }

  function _linkTokenPools(
    uint64 chainSelectorA,
    address tokenPoolA,
    uint64 chainSelectorB,
    address tokenPoolB
  ) internal {
    address tokenA = address(TokenPool(tokenPoolA).getToken());
    address tokenB = address(TokenPool(tokenPoolB).getToken());

    vm.startPrank(admin);

    {
      bytes[] memory remotePoolAddressesB = new bytes[](1);
      remotePoolAddressesB[0] = abi.encode(address(tokenPoolB));

      TokenPool.ChainUpdate[] memory chainUpdatesA = new TokenPool.ChainUpdate[](1);
      chainUpdatesA[0] = TokenPool.ChainUpdate({
        remoteChainSelector: chainSelectorB,
        remotePoolAddresses: remotePoolAddressesB,
        remoteTokenAddress: abi.encode(address(tokenB)),
        outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18}),
        inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18})
      });

      TokenPool(tokenPoolA).applyChainUpdates(new uint64[](0), chainUpdatesA);
    }

    {
      bytes[] memory remotePoolAddressesA = new bytes[](1);
      remotePoolAddressesA[0] = abi.encode(address(tokenPoolA));

      TokenPool.ChainUpdate[] memory chainUpdatesB = new TokenPool.ChainUpdate[](1);
      chainUpdatesB[0] = TokenPool.ChainUpdate({
        remoteChainSelector: chainSelectorA,
        remotePoolAddresses: remotePoolAddressesA,
        remoteTokenAddress: abi.encode(address(tokenA)),
        outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18}),
        inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 2000e18, rate: 1000e18})
      });

      TokenPool(tokenPoolB).applyChainUpdates(new uint64[](0), chainUpdatesB);
    }

    vm.stopPrank();
  }

  // Remove this contract from coverage
  function test() external pure {}
}
