// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ICheckerCounter} from "../interfaces/ICheckerCounter.sol";

/**
 * @title CheckerCounter
 * @dev A contract that counts the number of mints and burns for each minter and burner.
 */
contract CheckerCounter is Initializable, ICheckerCounter {
  using EnumerableSet for EnumerableSet.AddressSet;

  address internal immutable _governor;

  /* @custom:storage-location erc7201:token-governor.storage.CheckerCounter */
  struct CheckerCounterStorage {
    uint256 totalMinted;
    uint256 totalBurned;
    mapping(address => uint256) mints;
    mapping(address => uint256) burns;
    EnumerableSet.AddressSet minters;
    EnumerableSet.AddressSet burners;
  }

  // keccak256(abi.encode(uint256(keccak256("token-governor.storage.CheckerCounter")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant CheckerCounterStorageLocation =
    0xb9fc9c59b1e2dc149f534fa81c28e08b170a7a3e3d87580534c9aabfd4925b00;

  function _getCheckerCounterStorage() internal pure returns (CheckerCounterStorage storage s) {
    assembly ("memory-safe") {
      s.slot := CheckerCounterStorageLocation
    }
  }

  constructor(
    address governor
  ) {
    if (governor == address(0)) revert ZeroAddressNotAllowed();

    _governor = governor;

    initialize();
  }

  function initialize() public initializer {}

  modifier onlyGovernor() {
    _checkGovernor();
    _;
  }

  /**
   * @dev Returns the address of the governor.
   * @return The address of the governor.
   */
  function getGovernor() external view override returns (address) {
    return _governor;
  }

  /**
   * @dev Returns the total number of minters.
   * @return The total number of minters.
   */
  function getMintersCount() external view override returns (uint256) {
    return _getCheckerCounterStorage().minters.length();
  }

  /**
   * @dev Returns the total number of burners.
   * @return The total number of burners.
   */
  function getBurnersCount() external view override returns (uint256) {
    return _getCheckerCounterStorage().burners.length();
  }

  /**
   * @dev Returns the list of minters from start to end (not inclusive).
   * If end is greater than the number of minters, it will return the minters from start to the last minter.
   * @param start The starting index.
   * @param end The ending index.
   * @return minters The list of minters from start to end.
   */
  function getMinters(uint256 start, uint256 end) external view override returns (address[] memory minters) {
    return _getAddresses(_getCheckerCounterStorage().minters, start, end);
  }

  /**
   * @dev Returns the list of burners from start to end (not inclusive).
   * If end is greater than the number of burners, it will return the burners from start to the last burner.
   * @param start The starting index.
   * @param end The ending index.
   * @return burners The list of burners from start to end.
   */
  function getBurners(uint256 start, uint256 end) external view override returns (address[] memory burners) {
    return _getAddresses(_getCheckerCounterStorage().burners, start, end);
  }

  /**
   * @dev Returns the total amount minted.
   * @return The total amount minted.
   */
  function getTotalMinted() external view override returns (uint256) {
    return _getCheckerCounterStorage().totalMinted;
  }

  /**
   * @dev Returns the total amount burned.
   * @return The total amount burned.
   */
  function getTotalBurned() external view override returns (uint256) {
    return _getCheckerCounterStorage().totalBurned;
  }

  /**
   * @dev Returns the total amount minted by a given address.
   * @param minter The address of the minter.
   * @return The total amount minted by the given minter.
   */
  function getTotalMintedBy(
    address minter
  ) external view override returns (uint256) {
    return _getCheckerCounterStorage().mints[minter];
  }

  /**
   * @dev Returns the total amount burned by a given address.
   * @param burner The address of the burner.
   * @return The total amount burned by the given burner.
   */
  function getTotalBurnedBy(
    address burner
  ) external view override returns (uint256) {
    return _getCheckerCounterStorage().burns[burner];
  }

  /**
   * @dev Increments the mint count for a given minter.
   * @param amount The amount minted.
   * @param minter The address of the minter.
   */
  function checkMint(address, uint256 amount, address minter, bool) external override onlyGovernor {
    CheckerCounterStorage storage s = _getCheckerCounterStorage();

    if (amount > 0) s.minters.add(minter);
    uint256 totalGlobalMinted = (s.totalMinted += amount);
    unchecked {
      uint256 totalMinterMinted = (s.mints[minter] += amount);
      emit Minted(minter, amount, totalMinterMinted, totalGlobalMinted);
    }
  }

  /**
   * @dev Increments the burn count for a given burner.
   * @param amount The amount burned.
   * @param burner The address of the burner.
   */
  function checkBurn(address, uint256 amount, address burner, bool) external override onlyGovernor {
    CheckerCounterStorage storage s = _getCheckerCounterStorage();

    if (amount > 0) s.burners.add(burner);
    uint256 totalGlobalBurned = (s.totalBurned += amount);
    unchecked {
      uint256 totalBurnerBurned = (s.burns[burner] += amount);
      emit Burned(burner, amount, totalBurnerBurned, totalGlobalBurned);
    }
  }

  /**
   * @dev Checks if the caller is the governor.
   * Reverts if the caller is not the governor.
   */
  function _checkGovernor() internal view {
    if (msg.sender != _governor) revert OnlyGovernor();
  }

  /**
   * @dev Returns a list of addresses from an EnumerableSet from start to end (not inclusive).
   * If end is greater than the length of the set, it will return the addresses from start to the last address.
   * @param set The EnumerableSet to get the addresses from.
   * @param start The starting index.
   * @param end The ending index.
   * @return addresses The list of addresses from start to end.
   */
  function _getAddresses(
    EnumerableSet.AddressSet storage set,
    uint256 start,
    uint256 end
  ) internal view returns (address[] memory addresses) {
    if (start > end) revert InvalidRange(start, end);

    uint256 length = set.length();
    end = end > length ? length : end;

    if (start < end) {
      unchecked {
        addresses = new address[](end - start);
        for (uint256 i = start; i < end; i++) {
          addresses[i - start] = set.at(i);
        }
      }
    }
  }
}
