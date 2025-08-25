// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IExternalMinter} from "./interfaces/IExternalMinter.sol";

import {BurnMintExternalMinterTokenPoolAbstract} from "./BurnMintExternalMinterTokenPoolAbstract.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";

import {IERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Token Pool for tokens that are owned by an external minter
/// @notice The BurnMintWithExternalMinterTokenPool contract is a contract that implements the TokenPoolAbstract contract.
/// @dev It is used to manage operations for token that is owned by a ExternalMinter contract.
/// On `lockOrBurn`, the contract will call the burn function through the ExternalMinter contract.
/// On `releaseOrMint`, the contract will call the mint function through the ExternalMinter contract.
contract BurnMintWithExternalMinterTokenPool is BurnMintExternalMinterTokenPoolAbstract {
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
  ) TokenPool(token, localTokenDecimals, allowlist, rmnProxy, router) {
    i_minter = IExternalMinter(minter);
    // The token supplied to this constructor must match the token
    // returned by the minter, otherwise the deployment parameters are inconsistent.
    _validateTokenFromExternalMinter(token);
  }

  /// @notice Returns the type and version of this contract.
  /// @return The type and version string.
  function typeAndVersion() public pure virtual returns (string memory) {
    return "BurnMintWithExternalMinterTokenPool 1.6.0";
  }
}
