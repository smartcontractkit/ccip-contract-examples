// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IExternalMinter} from "./interfaces/IExternalMinter.sol";

import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";

import {IERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title BurnMintExternalMinterTokenPoolAbstract
/// @notice Base functionality for BurnMint Token Pools with external minter.
/// @dev Contains shared minter management and token management functionality.
abstract contract BurnMintExternalMinterTokenPoolAbstract is TokenPool {
  using SafeERC20 for IERC20;

  error TokenMismatch(IERC20 expected, IERC20 actual);

  /// @dev The external minter contract
  IExternalMinter internal immutable i_minter;

  /// @notice Get the address of the Minter contract.
  /// @return The address of the Minter contract.
  function getMinter() public view returns (address) {
    return address(i_minter);
  }

  // ================================================================
  // │                     Token Management                         │
  // ================================================================
  /// @notice Burn the amount of ERC20 tokens through the Minter contract.
  /// @param amount The amount of tokens to burn
  function _lockOrBurn(
    uint256 amount
  ) internal virtual override {
    // Token approval is needed as the minter will transfer the tokens to itself before burning them.
    getToken().safeApprove(address(i_minter), amount);
    i_minter.burn(amount);
  }

  /// @notice Mint the amount of ERC20 tokens through the Minter contract.
  /// @param receiver The address to mint tokens to
  /// @param amount The amount of tokens to mint
  function _releaseOrMint(address receiver, uint256 amount) internal virtual override {
    IExternalMinter(getMinter()).mint(receiver, amount);
  }

  /// @notice Validate that the token matches the one from the external minter.
  /// @param token The token to validate
  function _validateTokenFromExternalMinter(
    IERC20 token
  ) internal view virtual {
    IERC20 minterToken = IERC20(IExternalMinter(getMinter()).getToken());
    if (token != minterToken) {
      revert TokenMismatch(token, minterToken);
    }
  }
}
