// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../../stablecoin-governor/TokenGovernor.sol";
import "./Parameters.sol";

contract TokenGovernorScript is Script, Parameters {
  function run() external returns (address governor) {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    vm.startBroadcast(deployerPrivateKey);

    address owner = OWNER == address(0) ? deployer : OWNER;

    governor = address(new TokenGovernor(TOKEN, INITIAL_DELAY, owner));

    vm.stopBroadcast();
  }
}
