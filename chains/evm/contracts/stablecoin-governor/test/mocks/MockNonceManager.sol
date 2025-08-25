// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

contract MockNonceManager {
  mapping(uint64 => mapping(address => uint64)) public outboundNonces;
  mapping(uint64 => mapping(address => uint64)) public inboundNonces;

  function getIncrementedOutboundNonce(uint64 destChainSelector, address sender) external returns (uint64) {
    return ++outboundNonces[destChainSelector][sender];
  }

  function incrementInboundNonce(
    uint64 sourceChainSelector,
    uint64 expectedNonce,
    bytes calldata sender
  ) external returns (bool) {
    address senderAddr = abi.decode(sender, (address));
    uint64 nonce = inboundNonces[sourceChainSelector][senderAddr] + 1;
    if (nonce == expectedNonce) {
      inboundNonces[sourceChainSelector][senderAddr] = nonce;
      return true;
    }
    return false;
  }

  function test() external pure {}
}
