// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {HybridTokenPoolAbstract} from "./HybridTokenPoolAbstract.sol";
import {Pool} from "@chainlink/contracts-ccip/contracts/libraries/Pool.sol";
import {FastTransferTokenPoolAbstract} from
  "@chainlink/contracts-ccip/contracts/pools/FastTransferTokenPoolAbstract.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";

import {IERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title HybridWithExternalMinterFastTransferTokenPool
/// @notice Hybrid Token Pool with Fast Transfer support for tokens owned by an ExternalMinter contract.
/// @dev Combines hybrid lock/release and burn/mint functionality with fast transfer capabilities.
contract HybridWithExternalMinterFastTransferTokenPool is FastTransferTokenPoolAbstract, HybridTokenPoolAbstract {
  using SafeERC20 for IERC20;

  error InsufficientLiquidity(uint256 available, uint256 required);
  error InsufficientLiquidityForGroupUpdate(
    uint256 balanceBeforeMigration, uint256 balanceAfterMigration, uint256 accumulatedPoolFees
  );

  /// @dev Tracks the total accumulated fees in the pool, represented in token units.
  uint256 internal s_accumulatedPoolFees;

  /// @notice Constructor for the hybrid pool with fast transfer support.
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
  ) FastTransferTokenPoolAbstract(token, localTokenDecimals, allowlist, rmnProxy, router) {
    i_minter = minter;
    // The token supplied to this constructor must match the token
    // returned by the minter, otherwise the deployment parameters are inconsistent.
    _validateTokenFromExternalMinter(token);
  }

  /// @notice Returns the type and version of this contract.
  /// @return The type and version string.
  function typeAndVersion() public pure virtual returns (string memory) {
    return "HybridWithExternalMinterFastTransferTokenPool 1.6.0";
  }

  /// @notice Signals which version of the pool interface is supported.
  function supportsInterface(
    bytes4 interfaceId
  ) public pure virtual override(TokenPool, FastTransferTokenPoolAbstract) returns (bool) {
    return FastTransferTokenPoolAbstract.supportsInterface(interfaceId);
  }

  /// @notice Returns the router address.
  function getRouter() public view virtual override(TokenPool, FastTransferTokenPoolAbstract) returns (address) {
    return TokenPool.getRouter();
  }

  /// @notice Returns the locked tokens in the pool.
  /// @return The amount of locked tokens in the pool.
  function getLockedTokens() external view override returns (uint256) {
    return getToken().balanceOf(address(this)) - getAccumulatedPoolFees();
  }

  // ================================================================
  // │                      Group Management                        │
  // ================================================================
  /// @notice Updates remote chain groups while preserving accumulated pool fees.
  /// @dev Ensures fees are not lost. When switching from LOCK_AND_RELEASE to BURN_AND_MINT, burns the required tokens but retains at least the accumulated fees in the pool.
  /// @param groupUpdates Array of updates, each with a remote chain selector, the new group, and the supply amount to migrate.
  function updateGroups(
    GroupUpdate[] calldata groupUpdates
  ) public override {
    uint256 balanceBeforeMigration = getToken().balanceOf(address(this));
    super.updateGroups(groupUpdates);
    uint256 balanceAfterMigration = getToken().balanceOf(address(this));
    uint256 accumulatedFees = getAccumulatedPoolFees();
    if (balanceAfterMigration < accumulatedFees) {
      revert InsufficientLiquidityForGroupUpdate(balanceBeforeMigration, balanceAfterMigration, accumulatedFees);
    }
  }

  // ================================================================
  // │                    Liquidity Management                      │
  // ================================================================
  /// @notice Removes liquidity from the LOCK_AND_RELEASE group.
  /// @dev Can only be called by the rebalancer. The pool must retain at least the accumulated pool fees amount.
  /// @param amount The amount of tokens to remove from the pool.
  function withdrawLiquidity(
    uint256 amount
  ) external override {
    if (amount == 0) revert LiquidityAmountCannotBeZero();
    _validateRebalancer();
    IERC20 token = getToken();
    uint256 currentBalance = token.balanceOf(address(this));
    uint256 accumulatedFees = getAccumulatedPoolFees();
    if (currentBalance < amount + accumulatedFees) {
      revert InsufficientLiquidity(currentBalance, amount + accumulatedFees);
    }
    token.safeTransfer(msg.sender, amount);
    emit LiquidityRemoved(msg.sender, amount);
  }

  // ================================================================
  // │                      Fee Management                          │
  // ================================================================
  /// @notice Gets the accumulated pool fees.
  /// @return The accumulated pool fees in token units.
  function getAccumulatedPoolFees() public view override returns (uint256) {
    return s_accumulatedPoolFees;
  }

  /// @notice Withdraws all accumulated pool fees to the specified recipient.
  /// @dev Transfers the accumulated fees and resets the internal counter.
  /// @param recipient The address to receive the withdrawn fees.
  function withdrawPoolFees(
    address recipient
  ) external override onlyOwner {
    uint256 amount = getAccumulatedPoolFees();
    if (amount > 0) {
      s_accumulatedPoolFees = 0;
      IERC20(getToken()).safeTransfer(recipient, amount);
      emit PoolFeeWithdrawn(recipient, amount);
    }
  }

  // ================================================================
  // │                     Token Management                         │
  // ================================================================
  /// @notice Lock or burn tokens depending on group configuration.
  function lockOrBurn(
    Pool.LockOrBurnInV1 calldata lockOrBurnIn
  ) public virtual override(HybridTokenPoolAbstract, TokenPool) returns (Pool.LockOrBurnOutV1 memory) {
    return HybridTokenPoolAbstract.lockOrBurn(lockOrBurnIn);
  }

  /// @notice Release or mint tokens depending on group configuration.
  function releaseOrMint(
    Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
  ) public virtual override(HybridTokenPoolAbstract, TokenPool) returns (Pool.ReleaseOrMintOutV1 memory) {
    return HybridTokenPoolAbstract.releaseOrMint(releaseOrMintIn);
  }

  // ================================================================
  // │                      Fast Transfer Hooks                     │
  // ================================================================
  /// @notice Handles the token transfer on fast fill request at source chain.
  /// @param destChainSelector The chain selector for the destination chain of fast transfer request.
  /// @param sender The sender address.
  /// @param amount The amount to transfer.
  function _handleFastTransferLockOrBurn(
    uint64 destChainSelector,
    address sender,
    uint256 amount
  ) internal virtual override {
    IERC20 token = getToken();
    token.safeTransferFrom(sender, address(this), amount);
    _lockOrBurn(s_groups[destChainSelector], amount);
  }

  /// @notice Handles settlement when the request was not fast-filled.
  /// @param sourceChainSelector The chain selector for the source chain of fast transfer request.
  /// @param localSettlementAmount The amount to settle in local token.
  /// @param receiver The receiver address.
  function _handleSlowFill(
    bytes32,
    uint64 sourceChainSelector,
    uint256 localSettlementAmount,
    address receiver
  ) internal virtual override {
    _releaseOrMint(s_groups[sourceChainSelector], receiver, localSettlementAmount);
  }

  /// @notice Handles reimbursement when the request was fast-filled.
  /// @param sourceChainSelector The chain selector for the source chain of fast transfer request.
  /// @param filler The filler address to reimburse.
  /// @param fillerReimbursementAmount The amount to reimburse (what they provided + their fee).
  /// @param poolReimbursementAmount The amount to reimburse to the pool (the pool fee).
  function _handleFastFillReimbursement(
    bytes32,
    uint64 sourceChainSelector,
    address filler,
    uint256 fillerReimbursementAmount,
    uint256 poolReimbursementAmount
  ) internal virtual override {
    _releaseOrMint(s_groups[sourceChainSelector], address(this), fillerReimbursementAmount + poolReimbursementAmount);
    s_accumulatedPoolFees += poolReimbursementAmount;
    if (fillerReimbursementAmount > 0) {
      IERC20(getToken()).safeTransfer(filler, fillerReimbursementAmount);
    }
  }
}
