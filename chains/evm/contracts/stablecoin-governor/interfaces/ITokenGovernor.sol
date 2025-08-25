// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IExternalMinter} from "./IExternalMinter.sol";

interface ITokenGovernor is IExternalMinter {
  error ZeroAddressNotAllowed();
  error CallFailed(bytes error);
  error OnlyMinterOrBridge();
  error OnlyBurnerOrBridge();
  error MintFailed();
  error BurnFailed();
  error InvalidRecipient();
  error InvalidFrom();

  event CheckerUpdated(address indexed previousChecker, address indexed newChecker);
  event NativeMint(address indexed caller, address indexed recipient, uint256 amount);
  event BridgeMint(address indexed caller, address indexed recipient, uint256 amount);
  event NativeBurn(address indexed caller, address indexed from, uint256 amount);
  event BridgeBurn(address indexed caller, address indexed from, uint256 amount);
  event AccountFrozen(address indexed caller, address indexed account);
  event AccountUnfrozen(address indexed caller, address indexed account);
  event ContractPaused(address indexed caller);
  event ContractUnpaused(address indexed caller);
  event OwnershipTransferred(address indexed caller, address indexed newOwner);
  event OwnershipAccepted(address indexed caller);
  event TokensRecovered(
    address indexed caller, address indexed tokenAddress, address indexed recipient, uint256 amount
  );
  event GovernedTokensRecovered(
    address indexed caller, address indexed token, address indexed recipient, uint256 amount
  );
  event FrozenAccountDrained(address indexed caller, address indexed account);
  event TokenFunctionExecuted(address indexed caller, bytes data, bytes returnData);

  function MINTER_ROLE() external view returns (bytes32);
  function BRIDGE_MINTER_OR_BURNER_ROLE() external view returns (bytes32);
  function BURNER_ROLE() external view returns (bytes32);
  function FREEZER_ROLE() external view returns (bytes32);
  function UNFREEZER_ROLE() external view returns (bytes32);
  function PAUSER_ROLE() external view returns (bytes32);
  function UNPAUSER_ROLE() external view returns (bytes32);
  function RECOVERY_ROLE() external view returns (bytes32);
  function CHECKER_ADMIN_ROLE() external view returns (bytes32);
  function getChecker() external view returns (address);
  function getAdmins() external view returns (address[] memory);
  function getMinters() external view returns (address[] memory);
  function getBridgeMintersOrBurners() external view returns (address[] memory);
  function getBurners() external view returns (address[] memory);
  function getFreezers() external view returns (address[] memory);
  function getUnfreezers() external view returns (address[] memory);
  function getPausers() external view returns (address[] memory);
  function getUnpausers() external view returns (address[] memory);
  function getRecoveryManagers() external view returns (address[] memory);
  function getCheckerAdmins() external view returns (address[] memory);
  function getTokenBalance() external view returns (uint256);
  function setChecker(
    address newChecker
  ) external;
  function mint(
    uint256 amount
  ) external returns (bool);
  function burnFrom(address from, uint256 amount) external returns (bool);
  function freeze(
    address account
  ) external;
  function batchFreeze(
    address[] calldata accounts
  ) external;
  function unfreeze(
    address account
  ) external;
  function batchUnfreeze(
    address[] calldata accounts
  ) external;
  function pause() external;
  function unpause() external;
  function transferOwnership(
    address newOwner
  ) external;
  function acceptOwnership() external;
  function recoverERC20(address token, address recipient, uint256 amount) external;
  function recoverGovernedTokenERC20(address token, address recipient, uint256 amount) external;
  function drainFrozenAccount(
    address account
  ) external;
  function batchDrainFrozenAccounts(
    address[] calldata accounts
  ) external;
  function executeTokenFunction(
    bytes calldata data
  ) external payable returns (bytes memory returnData);
}
