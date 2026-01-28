// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {HybridWithExternalMinterTokenPool} from "../../stablecoin-governor/HybridWithExternalMinterTokenPool.sol";
import "./Parameters.sol";

import {IERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract HybridWithExternalMinterTokenPoolScript is Script, Parameters {
  function run() external returns (address tokenPool) {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    vm.startBroadcast(deployerPrivateKey);

    tokenPool = address(
      new HybridWithExternalMinterTokenPool(GOVERNOR, IERC20(TOKEN), TOKEN_DECIMALS, ALLOWLIST, RMN_PROXY, CCIP_ROUTER)
    );

    if (OWNER != address(0)) Ownable2Step(tokenPool).transferOwnership(OWNER);

    vm.stopBroadcast();
  }
}
