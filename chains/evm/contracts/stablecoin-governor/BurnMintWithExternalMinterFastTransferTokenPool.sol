// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IExternalMinter} from "./interfaces/IExternalMinter.sol";

import {BurnMintExternalMinterTokenPoolAbstract} from "./BurnMintExternalMinterTokenPoolAbstract.sol";
import {FastTransferTokenPoolAbstract} from
  "@chainlink/contracts-ccip/contracts/pools/FastTransferTokenPoolAbstract.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";

import {IERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Token Pool with fast transfer support; for tokens that are owned by an external minter
/// @notice The BurnMintWithExternalMinterFastTransferTokenPool contract is a contract that implements the TokenPoolAbstract contract.
/// @dev It is used to manage operations for token that is owned by a ExternalMinter contract.
/// On `lockOrBurn`, the contract will call the burn function through the ExternalMinter contract.
/// On `releaseOrMint`, the contract will call the mint function through the ExternalMinter contract.
contract BurnMintWithExternalMinterFastTransferTokenPool is
  BurnMintExternalMinterTokenPoolAbstract,
  FastTransferTokenPoolAbstract
{
  /// @notice Sets the immutable values for {i_minter}.
  /// @param minter The address of the minter contract
  /// @param token The token to be managed by the pool
  /// @param localTokenDecimals The decimals of the local token
  /// @param allowlist The allowlist of addresses
  /// @param rmnProxy The RMN proxy address
  /// @param router The address of the CCIP router
  constructor(
    address minter,
    IERC20 token,
    uint8 localTokenDecimals,
    address[] memory allowlist,
    address rmnProxy,
    address router
  ) FastTransferTokenPoolAbstract(token, localTokenDecimals, allowlist, rmnProxy, router) {
    i_minter = IExternalMinter(minter);
    // The token supplied to this constructor must match the token
    // returned by the minter, otherwise the deployment parameters are inconsistent.
    _validateTokenFromExternalMinter(token);
  }

  /// @notice Get the accumulated pool fees.
  /// @return The balance of the token in the pool, which represents the accumulated fees.
  function getAccumulatedPoolFees() public view override returns (uint256) {
    return getToken().balanceOf(address(this));
  }

  /// @notice Returns the router address.
  function getRouter() public view virtual override(TokenPool, FastTransferTokenPoolAbstract) returns (address) {
    return TokenPool.getRouter();
  }

  /// @notice Returns the type and version of this contract.
  /// @return The type and version string.
  function typeAndVersion() public pure virtual returns (string memory) {
    return "BurnMintWithExternalMinterFastTransferTokenPool 1.6.0";
  }

  function supportsInterface(
    bytes4 interfaceId
  ) public pure virtual override(FastTransferTokenPoolAbstract, TokenPool) returns (bool) {
    return FastTransferTokenPoolAbstract.supportsInterface(interfaceId);
  }

  // ================================================================
  // │                     Token Management                         │
  // ================================================================

  function _releaseOrMint(
    address receiver,
    uint256 amount
  ) internal virtual override(BurnMintExternalMinterTokenPoolAbstract, TokenPool) {
    BurnMintExternalMinterTokenPoolAbstract._releaseOrMint(receiver, amount);
  }

  function _lockOrBurn(
    uint256 amount
  ) internal override(BurnMintExternalMinterTokenPoolAbstract, TokenPool) {
    BurnMintExternalMinterTokenPoolAbstract._lockOrBurn(amount);
  }
}
