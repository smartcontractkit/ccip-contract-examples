// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IExternalMinter} from "./interfaces/IExternalMinter.sol";

import {Pool} from "@chainlink/contracts-ccip/contracts/libraries/Pool.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";

import {IERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from
  "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title HybridTokenPoolAbstract
/// @notice Base functionality for Hybrid Token Pools
/// @dev Contains shared group management, liquidity management, token management and rebalancer functionality.
abstract contract HybridTokenPoolAbstract is TokenPool {
  using SafeERC20 for IERC20;

  error InvalidGroupUpdate(uint64 remoteChainSelector, Group group);
  error LiquidityAmountCannotBeZero();
  error TokenMismatch(IERC20 expected, IERC20 actual);

  event RebalancerSet(address indexed oldRebalancer, address indexed newRebalancer);
  event GroupUpdated(uint64 indexed remoteChainSelector, Group indexed group);
  event LiquidityAdded(address indexed rebalancer, uint256 amount);
  event LiquidityRemoved(address indexed rebalancer, uint256 amount);
  event LiquidityMigrated(uint64 indexed remoteChainSelector, Group indexed group, uint256 remoteChainSupply);

  /// @dev By default, all chains are in the LOCK_AND_RELEASE group.
  enum Group {
    LOCK_AND_RELEASE, // 0: Lock tokens on source, release on destination
    BURN_AND_MINT // 1: Burn tokens on source, mint on destination

  }

  /// @dev Struct to hold group update information
  struct GroupUpdate {
    uint64 remoteChainSelector; // ─╮ Remote chain selector
    Group group; // ────────────────╯ New group to set
    uint256 remoteChainSupply; // Supply amount to migrate
  }

  /// @dev The external minter contract instance
  address internal immutable i_minter;
  /// @dev Address of the rebalancer contract
  address internal s_rebalancer;
  /// @dev Mapping that stores the operational mode configuration for each remote chain selector.
  /// (e.g., LOCK_AND_RELEASE or BURN_AND_MINT). By default, chains are set to LOCK_AND_RELEASE.
  mapping(uint64 remoteChainSelector => Group) internal s_groups;

  /// @notice Returns the locked tokens in the pool.
  /// @return The amount of locked tokens in the pool.
  function getLockedTokens() external view virtual returns (uint256) {
    return getToken().balanceOf(address(this));
  }

  /// @notice Returns the address of the rebalancer.
  /// @return The address of the rebalancer.
  function getRebalancer() external view returns (address) {
    return s_rebalancer;
  }

  /// @notice Returns the group of the given remote chain selector.
  /// @param remoteChainSelector The remote chain selector.
  /// @return The group of the given remote chain selector (0 = LOCK_AND_RELEASE, 1 = BURN_AND_MINT).
  function getGroup(
    uint64 remoteChainSelector
  ) external view returns (Group) {
    return s_groups[remoteChainSelector];
  }

  /// @notice Returns the external minter contract reference for a pool.
  /// @return The external minter contract instance.
  function getMinter() public view virtual returns (address) {
    return i_minter;
  }

  // ================================================================
  // │                      Chain Management                        │
  // ================================================================
  /// @notice Updates the group of the given list of remote chain selectors. Can only be called by the owner.
  /// @param groupUpdates The list of remote chain selectors and their corresponding groups.
  function updateGroups(
    GroupUpdate[] calldata groupUpdates
  ) public virtual onlyOwner {
    for (uint256 i = 0; i < groupUpdates.length; ++i) {
      GroupUpdate calldata groupUpdate = groupUpdates[i];
      Group group = s_groups[groupUpdate.remoteChainSelector];

      if (group == groupUpdate.group || !isSupportedChain(groupUpdate.remoteChainSelector)) {
        revert InvalidGroupUpdate(groupUpdate.remoteChainSelector, groupUpdate.group);
      }

      s_groups[groupUpdate.remoteChainSelector] = groupUpdate.group;

      // LIQUIDITY MIGRATION: Handle token backing changes when supply exists
      if (groupUpdate.remoteChainSupply > 0) {
        if (groupUpdate.group == Group.LOCK_AND_RELEASE) {
          // SWITCHING TO LOCK_AND_RELEASE: Mint backing tokens to this pool
          //
          // Migration Logic: If the remote chain has X tokens in circulation and is
          // switching to LOCK_AND_RELEASE, this pool must mint X tokens to itself
          // to provide the backing liquidity.
          //
          // CRITICAL: remoteChainSupply must include ALL tokens that need backing:
          // Tokens held by users on the remote chain
          // In-flight messages (tokens being transferred but not yet delivered)
          // The migration process should: 1) Pause bridge, 2) Resolve in-flight messages,
          // 3) Use totalSupply() which now includes all resolved transfers
          IExternalMinter(getMinter()).mint(address(this), groupUpdate.remoteChainSupply);
        } else {
          // SWITCHING TO BURN_AND_MINT: Burn backing tokens from this pool
          //
          // Migration Logic: If the remote chain is switching FROM LOCK_AND_RELEASE
          // TO BURN_AND_MINT, this pool no longer needs to hold backing tokens
          // for that chain's supply, so it burns them.
          //
          // CRITICAL: remoteChainSupply represents the total tokens this pool was backing,
          // which should equal the remote chain's total supply (including any resolved
          // in-flight messages that were delivered before the migration).
          getToken().safeApprove(address(getMinter()), groupUpdate.remoteChainSupply);
          IExternalMinter(getMinter()).burn(groupUpdate.remoteChainSupply);
        }
        emit LiquidityMigrated(groupUpdate.remoteChainSelector, groupUpdate.group, groupUpdate.remoteChainSupply);
      }
      emit GroupUpdated(groupUpdate.remoteChainSelector, groupUpdate.group);
    }
  }

  // ================================================================
  // │                    Liquidity Management                      │
  // ================================================================
  /// @notice Checks if the caller is the rebalancer.
  function _validateRebalancer() internal view {
    if (s_rebalancer != msg.sender) revert Unauthorized(msg.sender);
  }

  /// @notice Adds liquidity to the LOCK_AND_RELEASE group.
  /// @param amount The amount of tokens to add to the pool.
  function provideLiquidity(
    uint256 amount
  ) external {
    if (amount == 0) revert LiquidityAmountCannotBeZero();
    _validateRebalancer();
    IERC20(getToken()).safeTransferFrom(msg.sender, address(this), amount);
    emit LiquidityAdded(msg.sender, amount);
  }

  /// @notice Removes liquidity from the LOCK_AND_RELEASE group.
  /// @param amount The amount of tokens to remove from the pool.
  function withdrawLiquidity(
    uint256 amount
  ) external virtual {
    if (amount == 0) revert LiquidityAmountCannotBeZero();
    _validateRebalancer();
    IERC20(getToken()).safeTransfer(msg.sender, amount);
    emit LiquidityRemoved(msg.sender, amount);
  }

  // ================================================================
  // │                     Token Management                         │
  // ================================================================
  /// @notice Burns or locks tokens in the pool depending on the group configuration.
  /// @param lockOrBurnIn The lock or burn input parameters.
  /// @return The lock or burn output parameters.
  function lockOrBurn(
    Pool.LockOrBurnInV1 calldata lockOrBurnIn
  ) public virtual override returns (Pool.LockOrBurnOutV1 memory) {
    _validateLockOrBurn(lockOrBurnIn);
    _lockOrBurn(s_groups[lockOrBurnIn.remoteChainSelector], lockOrBurnIn.amount);
    emit TokenPool.LockedOrBurned({
      remoteChainSelector: lockOrBurnIn.remoteChainSelector,
      token: address(getToken()),
      sender: msg.sender,
      amount: lockOrBurnIn.amount
    });
    return Pool.LockOrBurnOutV1({
      destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
      destPoolData: _encodeLocalDecimals()
    });
  }

  /// @notice Mints or releases tokens from the pool to the recipient.
  /// @param releaseOrMintIn The release or mint input parameters.
  /// @return The release or mint output parameters.
  function releaseOrMint(
    Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
  ) public virtual override returns (Pool.ReleaseOrMintOutV1 memory) {
    uint256 localAmount = _calculateLocalAmount(
      releaseOrMintIn.sourceDenominatedAmount, _parseRemoteDecimals(releaseOrMintIn.sourcePoolData)
    );
    _validateReleaseOrMint(releaseOrMintIn, localAmount);
    _releaseOrMint(s_groups[releaseOrMintIn.remoteChainSelector], releaseOrMintIn.receiver, localAmount);
    emit TokenPool.ReleasedOrMinted({
      remoteChainSelector: releaseOrMintIn.remoteChainSelector,
      token: address(getToken()),
      sender: msg.sender,
      recipient: releaseOrMintIn.receiver,
      amount: localAmount
    });
    return Pool.ReleaseOrMintOutV1({destinationAmount: localAmount});
  }

  /// @notice Locks or burns the amount of ERC20 tokens depending on the group.
  /// @param group The group to use for the operation.
  /// @param amount The amount of tokens to lock or burn.
  function _lockOrBurn(Group group, uint256 amount) internal {
    if (group == Group.BURN_AND_MINT) {
      IERC20(getToken()).safeApprove(address(getMinter()), amount);
      IExternalMinter(getMinter()).burn(amount);
    }
  }

  /// @notice Releases or mints the amount of ERC20 tokens depending on the group.
  /// @param group The group to use for the operation.
  /// @param receiver The address to receive the tokens.
  /// @param amount The amount of tokens to release or mint.
  function _releaseOrMint(Group group, address receiver, uint256 amount) internal {
    if (group == Group.LOCK_AND_RELEASE) {
      // Ensure the tokens are only transferred to the receiver if the receiver is not the pool itself.
      // This prevents unnecessary self-transfers, such as when the pool reimburses itself for token pool fees,
      // which could lead to redundant operations or gas usage.
      if (receiver != address(this)) {
        IERC20(getToken()).safeTransfer(receiver, amount);
      }
    } else {
      IExternalMinter(getMinter()).mint(receiver, amount);
    }
  }

  // ================================================================
  // │                    Rebalancer Management                     │
  // ================================================================
  /// @notice Sets the rebalancer address.
  /// @dev Address(0) can be used to disable the rebalancer.
  /// @param rebalancer The address of the rebalancer.
  function setRebalancer(
    address rebalancer
  ) external onlyOwner {
    address oldRebalancer = s_rebalancer;
    s_rebalancer = rebalancer;
    emit RebalancerSet(oldRebalancer, rebalancer);
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
