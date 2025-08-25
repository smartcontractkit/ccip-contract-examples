// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {Internal} from "@chainlink/contracts-ccip/contracts/libraries/Internal.sol";

contract MockFeeQuoter {
  mapping(uint64 => uint256) private _fees;

  function setFee(uint64 chainSelector, uint256 fee) external {
    _fees[chainSelector] = fee;
  }

  function getValidatedFee(uint64 chainSelector, Client.EVM2AnyMessage memory) external view returns (uint256) {
    return _fees[chainSelector];
  }

  function processMessageArgs(
    uint64 destChainSelector,
    address,
    uint256,
    bytes calldata extraArgs,
    bytes calldata messageReceiver
  )
    external
    view
    returns (
      uint256 msgFeeJuels,
      bool isOutOfOrderExecution,
      bytes memory convertedExtraArgs,
      bytes memory tokenReceiver
    )
  {
    Client.GenericExtraArgsV2 memory extraArgsV2 = _parseUnvalidatedEVMExtraArgsFromBytes(extraArgs, 100_000);

    return (
      _fees[destChainSelector], extraArgsV2.allowOutOfOrderExecution, Client._argsToBytes(extraArgsV2), messageReceiver
    );
  }

  function processPoolReturnData(
    uint64,
    Internal.EVM2AnyTokenTransfer[] calldata onRampTokenTransfers,
    Client.EVMTokenAmount[] calldata
  ) external pure returns (bytes[] memory destExecDataPerToken) {
    destExecDataPerToken = new bytes[](onRampTokenTransfers.length);
    for (uint256 i = 0; i < onRampTokenTransfers.length; i++) {
      destExecDataPerToken[i] = abi.encode(100_000);
    }
  }

  function _parseUnvalidatedEVMExtraArgsFromBytes(
    bytes calldata extraArgs,
    uint64 defaultTxGasLimit
  ) private pure returns (Client.GenericExtraArgsV2 memory) {
    if (extraArgs.length == 0) {
      return Client.GenericExtraArgsV2({gasLimit: defaultTxGasLimit, allowOutOfOrderExecution: false});
    }

    bytes4 extraArgsTag = bytes4(extraArgs);
    bytes memory argsData = extraArgs[4:];

    if (extraArgsTag == Client.GENERIC_EXTRA_ARGS_V2_TAG) {
      return abi.decode(argsData, (Client.GenericExtraArgsV2));
    } else if (extraArgsTag == Client.EVM_EXTRA_ARGS_V1_TAG) {
      return Client.GenericExtraArgsV2({gasLimit: abi.decode(argsData, (uint256)), allowOutOfOrderExecution: false});
    }
    revert("MockFeeQuoter Invalid extra args tag");
  }

  function test() external pure {}
}
