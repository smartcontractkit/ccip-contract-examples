// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "../../interfaces/IGovernedToken.sol";

contract Stablecoin is ERC20PermitUpgradeable, Ownable2StepUpgradeable, PausableUpgradeable, IGovernedToken {
  mapping(address => bool) public frozen;

  function initialize(string memory _name, string memory _symbol) public initializer {
    __Context_init();
    __ERC20_init(_name, _symbol);
    __ERC20Permit_init(_name);
    __Ownable2Step_init();
    __Ownable_init(msg.sender);
    __Pausable_init();
  }

  /**
   * @dev Throws if account is frozen.
   */
  modifier notFrozen(
    address account
  ) {
    _notFrozen(account);
    _;
  }

  /**
   * @dev See {ERC20-_mint}.
   * @param amount Mint amount
   * @return True if successful
   * Can only be called by the current owner.
   */
  function mint(
    uint256 amount
  ) external override onlyOwner returns (bool) {
    _mint(_msgSender(), amount);
    emit Mint(_msgSender(), _msgSender(), amount);
    return true;
  }

  /**
   * @dev See {ERC20-_burn}.
   * @param amount Burn amount
   * @return True if successful
   * Can only be called by the current owner.
   */
  function burn(
    uint256 amount
  ) external override onlyOwner returns (bool) {
    _burn(_msgSender(), amount);
    emit Burn(_msgSender(), _msgSender(), amount);
    return true;
  }

  /**
   * @dev Adds account to frozen state.
   * Can only be called by the current owner.
   */
  function freeze(
    address account
  ) external override onlyOwner {
    frozen[account] = true;
    emit Freeze(_msgSender(), account);
  }

  /**
   * @dev Removes account from frozen state.
   * Can only be called by the current owner.
   */
  function unfreeze(
    address account
  ) external override onlyOwner {
    delete frozen[account];
    emit Unfreeze(_msgSender(), account);
  }

  /**
   * @dev Triggers stopped state.
   * Can only be called by the current owner.
   */
  function pause() external override onlyOwner {
    _pause();
  }

  /**
   * @dev Returns to normal state.
   * Can only be called by the current owner.
   */
  function unpause() external override onlyOwner {
    _unpause();
  }

  /**
   * @dev Unsupported. Leaves the contract without owner.
   */
  function renounceOwnership() public pure override {
    revert("Unsupported");
  }

  /**
   * @dev Transfers ownership of the contract to a new account (`newOwner`).
   * Can only be called by the current owner (checked by the Ownable2StepUpgradeable contract).
   */
  function transferOwnership(
    address newOwner
  ) public override(Ownable2StepUpgradeable, IGovernedToken) {
    Ownable2StepUpgradeable.transferOwnership(newOwner);
  }

  /**
   * @dev Accepts ownership of the contract.
   * Can only be called by the pending owner (checked by the Ownable2StepUpgradeable contract).
   */
  function acceptOwnership() public override(Ownable2StepUpgradeable, IGovernedToken) {
    Ownable2StepUpgradeable.acceptOwnership();
  }

  /**
   * @dev Throws if the account is frozen.
   * @param account The address to check
   */
  function _notFrozen(
    address account
  ) internal view {
    require(!frozen[account], "Account is frozen");
  }

  /**
   * @dev See {ERC20-_update}.
   * @param from Source address
   * @param to Destination address
   * @param amount Transfer amount
   */
  function _update(address from, address to, uint256 amount) internal override whenNotPaused {
    // Check if this is a transfer and not a mint or burn
    if (from != address(0) && to != address(0)) {
      _notFrozen(from);
      _notFrozen(to);
    }

    super._update(from, to, amount);
  }

  /**
   * @dev See {ERC20-_approve}.
   * @param owner_ Owners's address
   * @param spender Spender's address
   * @param value Allowance amount
   * @param emitEvent Emit event
   */
  function _approve(
    address owner_,
    address spender,
    uint256 value,
    bool emitEvent
  ) internal override whenNotPaused notFrozen(owner_) notFrozen(spender) {
    super._approve(owner_, spender, value, emitEvent);
  }

  function drain(
    address account
  ) external override {
    uint256 balance = balanceOf(account);
    _burn(account, balance);
  }

  function recoverERC20(address token, address recipient, uint256 amount) external override {
    IERC20(token).transfer(recipient, amount);
  }

  // Remove this contract from coverage
  function test() external pure {}
}
