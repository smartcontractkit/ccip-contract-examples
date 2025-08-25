// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {HybridTokenPoolAbstract} from "./HybridTokenPoolAbstract.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";

import {IERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title HybridWithExternalMinterTokenPool
/// @notice Token Pool for tokens owned by an ExternalMinter contract with hybrid functionality.
/// @dev Implements hybrid lock/release and burn/mint functionality for tokens owned by an ExternalMinter contract.
contract HybridWithExternalMinterTokenPool is HybridTokenPoolAbstract {
  using SafeERC20 for IERC20;

  /// @notice Constructor for the hybrid pool.
  /// @param minter The address of the minter contract.
  /// @param localTokenDecimals The decimals of the local token.
  /// @param allowlist The allowlist of addresses.
  /// @param rmnProxy The RMN proxy address.
  /// @param router The address of the CCIP router.
  constructor(
    address minter,
    IERC20 token,
    uint8 localTokenDecimals,
    address[] memory allowlist,
    address rmnProxy,
    address router
  ) TokenPool(token, localTokenDecimals, allowlist, rmnProxy, router) {
    i_minter = minter;
    // The token supplied to this constructor must match the token
    // returned by the minter, otherwise the deployment parameters are inconsistent.
    _validateTokenFromExternalMinter(token);
  }

  /// @notice Returns the type and version of this contract.
  /// @return The type and version string.
  function typeAndVersion() public pure virtual returns (string memory) {
    return "HybridWithExternalMinterTokenPool 1.6.0";
  }
}
