// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {AccessControlDefaultAdminRules} from
  "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IChecker} from "./interfaces/IChecker.sol";
import {IGovernedToken} from "./interfaces/IGovernedToken.sol";
import {ITokenGovernor} from "./interfaces/ITokenGovernor.sol";

/**
 * @title TokenGovernor
 * @dev Governance contract for managing a Token with permissioned functions.
 * It implements the IExternalMinter interface and provides access control for various roles.
 * This contract allows for minting, burning, freezing, unfreezing, pausing,
 * unpausing, and transferring ownership of the governed token.
 * Each permissioned function has its own role for granular access control.
 * It also allows for a checker contract to validate minting and burning operations.
 */
contract TokenGovernor is AccessControlDefaultAdminRules, ITokenGovernor {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  // Role definitions
  bytes32 public constant override MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant override BRIDGE_MINTER_OR_BURNER_ROLE = keccak256("BRIDGE_MINTER_OR_BURNER_ROLE");
  bytes32 public constant override BURNER_ROLE = keccak256("BURNER_ROLE");
  bytes32 public constant override FREEZER_ROLE = keccak256("FREEZER_ROLE");
  bytes32 public constant override UNFREEZER_ROLE = keccak256("UNFREEZER_ROLE");
  bytes32 public constant override PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 public constant override UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
  bytes32 public constant override RECOVERY_ROLE = keccak256("RECOVERY_ROLE");
  bytes32 public constant override CHECKER_ADMIN_ROLE = keccak256("CHECKER_ADMIN_ROLE");

  // Token being governed (immutable)
  IGovernedToken internal immutable i_token;

  // Checker contract
  address internal s_checker;

  mapping(bytes32 role => EnumerableSet.AddressSet) private _roleMembers;

  /**
   * @dev Constructor sets up the initial admin roles and token address (immutable),
   * and initializes the initial delay and default admin.
   * @param token The address of the token contract to be governed
   * @param initialDelay The initial delay for the contract
   * @param initialDefaultAdmin The address of the initial default admin
   */
  constructor(
    address token,
    uint48 initialDelay,
    address initialDefaultAdmin
  ) AccessControlDefaultAdminRules(initialDelay, initialDefaultAdmin) {
    if (token == address(0)) revert ZeroAddressNotAllowed();

    i_token = IGovernedToken(token);
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual override returns (bool) {
    return interfaceId == type(IAccessControlEnumerable).interfaceId || super.supportsInterface(interfaceId);
  }

  /**
   * @dev Returns one of the accounts that have `role`. `index` must be a
   * value between 0 and {getRoleMemberCount}, non-inclusive.
   *
   * Role bearers are not sorted in any particular way, and their ordering may
   * change at any point.
   *
   * WARNING: When using {getRoleMember} and {getRoleMemberCount}, make sure
   * you perform all queries on the same block. See the following
   * https://forum.openzeppelin.com/t/iterating-over-elements-on-enumerableset-in-openzeppelin-contracts/2296[forum post]
   * for more information.
   */
  function getRoleMember(bytes32 role, uint256 index) public view virtual returns (address) {
    return _roleMembers[role].at(index);
  }

  /**
   * @dev Returns the number of accounts that have `role`. Can be used
   * together with {getRoleMember} to enumerate all bearers of a role.
   */
  function getRoleMemberCount(
    bytes32 role
  ) public view virtual returns (uint256) {
    return _roleMembers[role].length();
  }

  /**
   * @dev Return all accounts that have `role`
   *
   * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
   * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
   * this function has an unbounded cost, and using it as part of a state-changing function may render the function
   * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
   */
  function getRoleMembers(
    bytes32 role
  ) public view virtual returns (address[] memory) {
    return _roleMembers[role].values();
  }

  /*
     * @dev Get the address of the token contract
     * @return Address of the token contract
     */
  function getToken() external view override returns (address) {
    return address(i_token);
  }

  /**
   * @dev Get the address of the checker contract
   * @return Address of the checker contract
   */
  function getChecker() external view override returns (address) {
    return s_checker;
  }

  /**
   * @dev Get all admins (holders of DEFAULT_ADMIN_ROLE)
   * @return Array of admin addresses
   */
  function getAdmins() external view override returns (address[] memory) {
    return getRoleMembers(DEFAULT_ADMIN_ROLE);
  }

  /**
   * @dev Get all addresses with MINTER_ROLE
   * @return Array of minter addresses
   */
  function getMinters() external view override returns (address[] memory) {
    return getRoleMembers(MINTER_ROLE);
  }

  /**
   * @dev Get all addresses with BRIDGE_MINTER_ROLE
   * @return Array of bridge minter addresses
   */
  function getBridgeMintersOrBurners() external view override returns (address[] memory) {
    return getRoleMembers(BRIDGE_MINTER_OR_BURNER_ROLE);
  }

  /**
   * @dev Get all addresses with BURNER_ROLE
   * @return Array of burner addresses
   */
  function getBurners() external view override returns (address[] memory) {
    return getRoleMembers(BURNER_ROLE);
  }

  /**
   * @dev Get all addresses with FREEZER_ROLE
   * @return Array of freezer addresses
   */
  function getFreezers() external view override returns (address[] memory) {
    return getRoleMembers(FREEZER_ROLE);
  }

  /**
   * @dev Get all addresses with UNFREEZER_ROLE
   * @return Array of unfreezer addresses
   */
  function getUnfreezers() external view override returns (address[] memory) {
    return getRoleMembers(UNFREEZER_ROLE);
  }

  /**
   * @dev Get all addresses with PAUSER_ROLE
   * @return Array of pauser addresses
   */
  function getPausers() external view override returns (address[] memory) {
    return getRoleMembers(PAUSER_ROLE);
  }

  /**
   * @dev Get all addresses with UNPAUSER_ROLE
   * @return Array of unpauser addresses
   */
  function getUnpausers() external view override returns (address[] memory) {
    return getRoleMembers(UNPAUSER_ROLE);
  }

  /**
   * @dev Get all addresses with RECOVERY_ROLE
   * @return Array of recovery manager addresses
   */
  function getRecoveryManagers() external view override returns (address[] memory) {
    return getRoleMembers(RECOVERY_ROLE);
  }

  /**
   * @dev Get all addresses with CHECKER_ADMIN_ROLE
   * @return Array of checker admin addresses
   */
  function getCheckerAdmins() external view override returns (address[] memory) {
    return getRoleMembers(CHECKER_ADMIN_ROLE);
  }

  /**
   * @dev Check the current balance of the governed token held by this contract
   * @return Balance of the token
   */
  function getTokenBalance() external view override returns (uint256) {
    return i_token.balanceOf(address(this));
  }

  /**
   * @dev Set the checker contract address (requires CHECKER_ADMIN_ROLE)
   * @param newChecker The address of the new checker contract
   */
  function setChecker(
    address newChecker
  ) external override onlyRole(CHECKER_ADMIN_ROLE) {
    address oldChecker = s_checker;
    s_checker = newChecker;
    emit CheckerUpdated(oldChecker, newChecker);
  }

  // ===========================================================
  // =============== Token passthrough functions ===============
  // ===========================================================

  /**
   * @dev Mint new tokens and transfer them to the caller (requires MINTER_ROLE or BRIDGE_MINTER_ROLE)
   * @param amount Amount of tokens to mint
   * @return True if successful
   */
  function mint(
    uint256 amount
  ) external override returns (bool) {
    _mint( /* recipient = */ msg.sender, amount);
    return true;
  }

  /**
   * @dev Mint tokens to a specific address (requires MINTER_ROLE or BRIDGE_MINTER_ROLE)
   * @param recipient Address to receive the minted tokens
   * @param amount Amount of tokens to mint
   * @return True if successful
   */
  function mint(address recipient, uint256 amount) external override returns (bool) {
    _mint(recipient, amount);
    return true;
  }

  /**
   * @dev Burn tokens from the caller (requires BURNER_ROLE).
   * The sender must have approved this contract to spend the tokens
   * @param amount Amount of tokens to burn
   * @return True if successful
   */
  function burn(
    uint256 amount
  ) external override returns (bool) {
    _burn( /* from = */ msg.sender, amount);
    return true;
  }

  /**
   * @dev Burn tokens from a specific address (requires BURNER_ROLE)
   * @param from Address to burn tokens from. Must have an approval set on this contract
   * @param amount Amount of tokens to burn
   * @return True if successful
   */
  function burnFrom(address from, uint256 amount) external override returns (bool) {
    _burn(from, amount);
    return true;
  }

  /**
   * @dev Add an address to frozen state (requires FREEZER_ROLE)
   * @param account Address to freeze
   */
  function freeze(
    address account
  ) external override onlyRole(FREEZER_ROLE) {
    _freeze(account);
  }

  /**
   * @dev Add a list of addresses to frozen state (requires FREEZER_ROLE)
   * @param accounts List of addresses to freeze
   */
  function batchFreeze(
    address[] calldata accounts
  ) external override onlyRole(FREEZER_ROLE) {
    for (uint256 i = 0; i < accounts.length; i++) {
      _freeze(accounts[i]);
    }
  }

  /**
   * @dev Remove an address from frozen state (requires UNFREEZER_ROLE)
   * @param account Address to unfreeze
   */
  function unfreeze(
    address account
  ) external override onlyRole(UNFREEZER_ROLE) {
    _unfreeze(account);
  }

  /**
   * @dev Remove a list of addresses from frozen state (requires UNFREEZER_ROLE)
   * @param accounts List of addresses to unfreeze
   */
  function batchUnfreeze(
    address[] calldata accounts
  ) external override onlyRole(UNFREEZER_ROLE) {
    for (uint256 i = 0; i < accounts.length; i++) {
      _unfreeze(accounts[i]);
    }
  }

  /**
   * @dev Pause all token transfers (requires PAUSER_ROLE)
   */
  function pause() external override onlyRole(PAUSER_ROLE) {
    i_token.pause();
    emit ContractPaused(msg.sender);
  }

  /**
   * @dev Unpause token transfers (requires UNPAUSER_ROLE)
   */
  function unpause() external override onlyRole(UNPAUSER_ROLE) {
    i_token.unpause();
    emit ContractUnpaused(msg.sender);
  }

  /**
   * @dev Begin transfer of ownership (requires DEFAULT_ADMIN_ROLE)
   * @param newOwner Address of the new owner
   */
  function transferOwnership(
    address newOwner
  ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    i_token.transferOwnership(newOwner);
    emit OwnershipTransferred(msg.sender, newOwner);
  }

  /**
   * @dev Complete transfer of ownership (requires DEFAULT_ADMIN_ROLE)
   */
  function acceptOwnership() external override onlyRole(DEFAULT_ADMIN_ROLE) {
    i_token.acceptOwnership();
    emit OwnershipAccepted(msg.sender);
  }

  /**
   * @dev Emergency recovery of tokens accidentally sent to this contract (requires RECOVERY_ROLE)
   * @param token Address of token to recover
   * @param recipient Address to receive the tokens
   * @param amount Amount to recover
   */
  function recoverERC20(address token, address recipient, uint256 amount) external override onlyRole(RECOVERY_ROLE) {
    if (recipient == address(0)) revert ZeroAddressNotAllowed();
    IERC20(token).safeTransfer(recipient, amount);
    emit TokensRecovered(msg.sender, token, recipient, amount);
  }

  /**
   * @dev Emergency recovery of tokens sent to the governed token contract (requires RECOVERY_ROLE)
   * @param token Address of token to recover
   * @param recipient Address to receive the tokens
   * @param amount Amount to recover
   */
  function recoverGovernedTokenERC20(
    address token,
    address recipient,
    uint256 amount
  ) external override onlyRole(RECOVERY_ROLE) {
    i_token.recoverERC20(token, recipient, amount);
    emit GovernedTokensRecovered(msg.sender, token, recipient, amount);
  }

  /**
   * @dev Drains the tokens from a frozen account (requires DEFAULT_ADMIN_ROLE)
   * @param account Address to drain tokens from
   */
  function drainFrozenAccount(
    address account
  ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    _drainFrozenAccount(account);
  }

  /**
   * @dev Drains the tokens from a list of frozen accounts (requires DEFAULT_ADMIN_ROLE)
   * @param accounts List of addresses to drain tokens from
   */
  function batchDrainFrozenAccounts(
    address[] calldata accounts
  ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    for (uint256 i = 0; i < accounts.length; i++) {
      _drainFrozenAccount(accounts[i]);
    }
  }

  /**
   * @dev Execute a custom function call on the token (requires DEFAULT_ADMIN_ROLE)
   * This allows for calling any function not explicitly defined in this contract.
   * Any native token sent with the call will be forwarded to the token contract.
   * @param data Function call data
   * @return returnData The data returned by the call
   */
  function executeTokenFunction(
    bytes calldata data
  ) external payable override onlyRole(DEFAULT_ADMIN_ROLE) returns (bytes memory) {
    (bool success, bytes memory returnData) = address(i_token).call{value: msg.value}(data);
    if (!success) revert CallFailed(returnData);

    emit TokenFunctionExecuted(msg.sender, data, returnData);

    return returnData;
  }

  // ==================================================
  // =============== Internal Functions ===============
  // ==================================================

  /**
   * @dev Internal function to mint tokens with checker validation and role verification
   * @param recipient Address to receive the minted tokens (can not be this contract)
   * @param amount Amount of tokens to mint
   */
  function _mint(address recipient, uint256 amount) internal {
    // Check that the caller has either MINTER_ROLE or BRIDGE_MINTER_OR_BURNER_ROLE
    // and that the recipient is not this contract
    bool isBridge = hasRole(BRIDGE_MINTER_OR_BURNER_ROLE, msg.sender);
    if (!isBridge && !hasRole(MINTER_ROLE, msg.sender)) revert OnlyMinterOrBridge();
    if (recipient == address(this)) revert InvalidRecipient();

    // Run checker if it is set
    address checker = s_checker;
    if (checker != address(0)) {
      IChecker(checker).checkMint(recipient, amount, msg.sender, isBridge);
    }

    _tokenMint(recipient, amount);

    if (isBridge) {
      emit BridgeMint(msg.sender, recipient, amount);
    } else {
      emit NativeMint(msg.sender, recipient, amount);
    }
  }

  /**
   * @dev Internal function to burn tokens with checker validation and role verification
   * @param from Address whose tokens are being burned
   * @param amount Amount of tokens to burn
   */
  function _burn(address from, uint256 amount) internal {
    // Check that the caller has either BURNER_ROLE or BRIDGE_MINTER_OR_BURNER_ROLE
    bool isBridge = hasRole(BRIDGE_MINTER_OR_BURNER_ROLE, msg.sender);
    if (!isBridge && !hasRole(BURNER_ROLE, msg.sender)) revert OnlyBurnerOrBridge();
    if (from == address(this)) revert InvalidFrom();

    // Run checker if it is set
    address checker = s_checker;
    if (checker != address(0)) {
      IChecker(checker).checkBurn(from, amount, msg.sender, isBridge);
    }

    _tokenBurn(from, amount);

    if (isBridge) {
      emit BridgeBurn(msg.sender, from, amount);
    } else {
      emit NativeBurn(msg.sender, from, amount);
    }
  }

  /**
   * @dev Internal function to freeze an account
   * @param account Address to freeze
   */
  function _freeze(
    address account
  ) internal {
    i_token.freeze(account);
    emit AccountFrozen(msg.sender, account);
  }

  /**
   * @dev Internal function to remove an account from frozen state
   * @param account Address to unfreeze
   */
  function _unfreeze(
    address account
  ) internal {
    i_token.unfreeze(account);
    emit AccountUnfrozen(msg.sender, account);
  }

  /**
   * @dev Internal function to drain tokens from a frozen account
   * @param account Address to drain tokens from
   */
  function _drainFrozenAccount(
    address account
  ) internal {
    i_token.drain(account);
    emit FrozenAccountDrained(msg.sender, account);
  }

  /**
   * @dev Internal function to mint tokens directly to a recipient
   * In this case, mint the token to this contract and then transfer it to the recipient
   * @param recipient Address to receive the minted tokens
   * @param amount Amount of tokens to mint
   */
  function _tokenMint(address recipient, uint256 amount) internal virtual {
    if (!i_token.mint(amount)) revert MintFailed();
    IERC20(i_token).safeTransfer(recipient, amount);
  }

  /**
   * @dev Internal function to burn tokens from a specific address
   * In this case, transfer the tokens from the address to this contract and then burn them,
   * This requires the `from` address to have approved this contract to spend the tokens.
   * @param from Address whose tokens are being burned
   * @param amount Amount of tokens to burn
   */
  function _tokenBurn(address from, uint256 amount) internal virtual {
    IERC20(i_token).safeTransferFrom(from, address(this), amount);
    if (!i_token.burn(amount)) revert BurnFailed();
  }

  /**
   * @dev Overload {AccessControlDefaultAdminRules-_grantRole} to track enumerable memberships
   */
  function _grantRole(bytes32 role, address account) internal virtual override returns (bool) {
    bool granted = super._grantRole(role, account);
    if (granted) {
      _roleMembers[role].add(account);
    }
    return granted;
  }

  /**
   * @dev Overload {AccessControlDefaultAdminRules-_revokeRole} to track enumerable memberships
   */
  function _revokeRole(bytes32 role, address account) internal virtual override returns (bool) {
    bool revoked = super._revokeRole(role, account);
    if (revoked) {
      _roleMembers[role].remove(account);
    }
    return revoked;
  }
}
