// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../../stablecoin-governor/BurnMintWithExternalMinterTokenPool.sol";

import {IExternalMinter} from "../../stablecoin-governor/interfaces/IExternalMinter.sol";
import "./Parameters.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract BurnMintWithExternalMinterTokenPoolScript is Script, Parameters {
  function run() external returns (address tokenPool) {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    vm.startBroadcast(deployerPrivateKey);

    address token = IExternalMinter(GOVERNOR).getToken();
    tokenPool = address(
      new BurnMintWithExternalMinterTokenPool(
        GOVERNOR, IERC20(token), TOKEN_DECIMALS, ALLOWLIST, RMN_PROXY, CCIP_ROUTER
      )
    );

    if (OWNER != address(0)) Ownable2Step(tokenPool).transferOwnership(OWNER);

    vm.stopBroadcast();
  }
}
