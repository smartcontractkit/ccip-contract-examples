# Token Governor

## Overview

The Token Governor is a governance contract designed to act as an ownership wrapper or proxy for a governed token (a contract that is owned by a single owner). It provides enhanced functionality and security by introducing role-based access control (RBAC) and additional features to support operational security and bridging processes.

Key features include:

- Granting additional minters access for bridging or native issuance processes.
- Ensuring that a Proof of Reserves check can be run on every mint operation.
- Providing robust RBAC to enable best-in-class operational security patterns.

This contract is ideal for token projects that require more granular control and security over minting, burning, and other administrative functions.

## Contracts

### [TokenGovernor.sol](../stablecoin-governor/TokenGovernor.solovernor.sol)

The `TokenGovernor` contract is the core of this repository. It acts as a governance layer for a token that follows the `IGovernedToken` interface, providing the following functionalities:

- **Role-Based Access Control (RBAC):** Granular roles such as `MINTER_ROLE`, `BURNER_ROLE`, `FREEZER_ROLE`, and others to manage permissions for specific actions.
- **Minting and Burning:** Allows controlled minting and burning of tokens, with optional Proof of Reserves checks.
- **Freezing and Unfreezing Accounts:** Enables freezing and unfreezing of accounts to enhance security.
- **Pausing and Unpausing Transfers:** Provides the ability to pause and unpause all token transfers.
- **Ownership Management:** Facilitates secure transfer of ownership of the token contract.
- **Emergency Recovery:** Allows recovery of tokens accidentally sent to the contract.
- **Custom Function Execution:** Enables execution of custom functions on the token contract for advanced use cases.

The contract integrates with OpenZeppelin's `AccessControlEnumerable` for RBAC and uses `SafeERC20` for secure token operations.

### [CheckerCounter.sol](checkers/CheckerCounter.sol)

The `CheckerCounter` contract is a minimal implementation of a checker contract. It tracks the number of mint and burn operations performed by specific addresses.

### [TokenPoolAbstract](../stablecoin-governor/TokenPoolAbstract.solbstract.sol)

This is an abstract contract that extends Chainlink's `TokenPool` and provides the foundational logic for locking, burning, releasing, and minting tokens. It defines the following key methods:

- `lockOrBurn`: Locks or burns tokens on the source chain.
- `releaseOrMint`: Releases or mints tokens on the destination chain.

The actual implementation of `_lockOrBurn` and `_releaseOrMint` is left to derived contracts.

### [BurnMintWithExternalMinterTokenPool](../stablecoin-governor/BurnMintWithExternalMinterTokenPool.solkenPool.sol)

This is a concrete implementation of the `TokenPoolAbstract` designed for tokens that are minted and burned by an external minter. It provides the following functionalities:

- `lockOrBurn`: Burns tokens on the source chain using the external minter.
- `releaseOrMint`: Mints tokens on the destination chain using the external minter.

> [!NOTE]  
> The `BurnMintWithExternalMinterTokenPool` might require more gas than the default 100k gas forwarded with token transfers.
> In the case of the `TokenGovernor` with the `CheckerCounter` checker, the `lockOrBurn` and `releaseOrMint` functions require at least 300k gas to be executed successfully.

### [HybridWithExternalMinterTokenPool](../stablecoin-governor/HybridWithExternalMinterTokenPool.solkenPool.sol)

This contract inherits from the `BurnMintWithExternalMinterTokenPool` and implements two groups of chains:

- **LOCK_AND_RELEASE:** The token of this group will be locked on the source chain and released on the destination chain. By default, any newly added chain will be part of this group.
- **BURN_AND_MINT:** The token of this group will be burned on the source chain and minted on the destination chain.

The `HybridWithExternalMinterTokenPool` contract allows for a hybrid approach to token transfers, where some chains use the lock-and-release mechanism while others use the burn-and-mint mechanism.

It also adds functions to update the group of a chain and to provide or remove lock-and-release liquidity (for example, during a chain migration). The update function also allows to mint tokens (in the case of a migration from a burn-and-mint to a lock-and-release chain) or to burn tokens (in the case of a migration from a lock-and-release to a burn-and-mint chain) for easier migration.

> ![!NOTE]
> The `HybridWithExternalMinterTokenPool` might require more gas than the default 100k gas forwarded with token transfers.
> In the case of the `TokenGovernor` with the `CheckerCounter` checker, the `lockOrBurn` and `releaseOrMint` functions for `BURN_AND_MINT` chains require at least 300k gas to be executed successfully. `LOCK_AND_RELEASE` chains do not require more gas than the default 100k gas.

## Usage

This repository uses yarn for package management and foundry for smart contract development.

### Documentation

- [Foundry](https://book.getfoundry.sh/)
- [Yarn](https://classic.yarnpkg.com/lang/en/docs/)

### Environment Setup

First, copy the `.env.example` file to `.env`.

```shell
$ cp .env.example .env
```

Then, update the `.env` file with the appropriate values.

### Build

```shell
$ yarn build
```

### Test

```shell
$ yarn test
```

### Deploy

```shell
$ yarn deploy <path-to-script> --rpc-url <rpc-url> --verifier <verifier> --verifier-api-key <verifier-api-key> --verifier-api-url <verifier-api-url>
```

Example:
Note that if etherscan is used as a verifier, the `--verifier-api-url` is not required.

```shell
$ yarn deploy script/TokenGovernor.s.sol --rpc-url https://api.avax.network/ext/bc/C/rpc --verifier etherscan --verifier-api-key $ETHERSCAN_API_KEY
```
