# Hooks Trampoline

Hooks are a CoW Protocol feature that allow traders to specify custom Ethereum
calls as part of their order to get executed atomically in the same transaction
as they trade.

The `HooksTrampoline` contract protects the protocol from two things:

- Executing calls from the privileged context of the settlement contract. Fees
  are accrued in the contract, and users could simply specify hooks that
  `ERC20.transfer(user, amount)` if the calling context for user hooks were the
  settlement contract.
- Reverting unnecessary hooks during a settlement. This can cause a two issues:
  - `Interaction`s from the settlement contract are called with all remaining
    `gasleft()`. This means, that a revert from an `INVALID` opcode for example,
    would consume 63/64ths of the total transaction gas. This means that hooks
    can make settlements extremely expensive for nothing.
  - Other orders being executed as part of the settlement would also not be
    included.

As such, the `HooksTrampoline` contract is designed to execute user-specified
hooks:

1. From an unprivileged context (the `HooksTrampoline` contract instead of the
   CoW Protocol settlement contract).
2. Specify a gas limit, to cap `INVALID` opcodes from consuming too much gas.
3. Allow the calls to revert.

In addition, the `HooksTrampoline` also only allows calls from the settlement
contract. This means that hook implementations can add checks that ensure that
they are only called from within a settlement:

```solidity
require(msg.sender == HOOKS_TRAMPOLINE_ADDRESS, "not a settlement");
```

## Settlement Diagram

```mermaid
sequenceDiagram
    participant Solver
    participant Settlement
    participant HooksTrampoline
    participant Hook

    Solver->>Settlement: settle
    activate Settlement

    Settlement->>HooksTrampoline: execute
    activate HooksTrampoline
    loop pre-hooks
        HooksTrampoline->>Hook: call
        activate Hook

        Hook->>HooksTrampoline: return/revert
        deactivate Hook
    end
    HooksTrampoline->>Settlement: return
    deactivate HooksTrampoline

    Settlement->>Settlement: swap

    Settlement->>HooksTrampoline: execute
    activate HooksTrampoline
    loop post-hooks
        HooksTrampoline->>Hook: call
        activate Hook

        Hook->>HooksTrampoline: return/revert
        deactivate Hook
    end
    HooksTrampoline->>Settlement: return
    deactivate HooksTrampoline


    Settlement->>Solver: return
    deactivate Settlement
```

## Development

### Installation

This project uses [Foundry](https://book.getfoundry.sh/).

Additional dependencies can be installed with:

```sh
forge install
```

### Test

```sh
forge test
```

### Deployment

Copy `.env.sample` to `.env` and fill each variable with the necessary
information.

You can do a test run of the transaction with the following command:

```sh
source .env
forge script script/DeployHooksTrampoline.s.sol -vvvv --rpc-url "$ETH_RPC_URL"
```

The following command executes the deployment transaction onchain and verifies
the contract code on the block explorer.

```sh
source .env
forge script script/DeployHooksTrampoline.s.sol -vvvv --rpc-url "$ETH_RPC_URL" --verify --verify-url $VERIFIER_URL --broadcast
```

This contract uses deterministic deployments.
The official deployment addresses for all supported chains can be found in the
file `networks.json`.
Entries are manually added to that file after each deployment to a new chain.

## Verification

If you deployed the contract passing `--verify`, the contract will be verified so you can skip this step. However, if you didn't, or the verification failed, you can verify the contract manually with the following command:

```sh
source .env

forge verify-contract <address> src/HooksTrampoline.sol:HooksTrampoline --guess-constructor-args  --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url $VERIFIER_URL --watch
```