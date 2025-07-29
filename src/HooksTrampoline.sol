// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8;

/// @title CoW Protocol Hooks Trampoline
/// @dev A trampoline contract for calling user-specified hooks. It ensures that
/// user-specified calls are not executed from a privileged context, and that
/// reverts do not prevent settlements from executing.
/// @author CoW Developers
contract HooksTrampoline {
    /// @dev A user-specified hook.
    struct Hook {
        address target;
        bytes callData;
        uint256 gasLimit;
    }

    /// @dev Error indicating that the trampoline was not called from the CoW
    /// Protocol settlement contract.
    error NotASettlement();

    /// @dev Error indicating that the gas left is less than the gas limit of the hook.
    error NotEnoughGas();

    /// @dev The address of the CoW Protocol settlement contract.
    address public immutable settlement;

    /// @param settlement_ The address of the CoW protocol settlement contract.
    constructor(address settlement_) {
        settlement = settlement_;
    }

    /// @dev Modifier that ensures that the `msg.sender` is the CoW Protocol
    /// settlement contract. Methods with this modifier are guaranteed to only
    /// be called as part of a CoW Protocol settlement.
    modifier onlySettlement() {
        if (msg.sender != settlement) {
            revert NotASettlement();
        }
        _;
    }

    /// @dev Executes the specified hooks. This function will revert if not
    /// called by the CoW Protocol settlement contract. This allows hooks to be
    /// semi-permissioned, ensuring that they are only executed as part of a CoW
    /// Protocol settlement. Additionally, hooks are called with a gas limit,
    /// and are allowed to revert. This is done in order to prevent badly
    /// configured user-specified hooks from consuming more gas than expected
    /// (for example, if a hook were to revert with an `INVALID` opcode) or
    /// causing an otherwise valid settlement to revert, effectively
    /// DoS-ing other orders.
    /// Note: The trampoline tries to ensure that the hook is called with
    /// exactly the gas limit specified in the hook, however in some
    /// circumstances it may be a bit smaller than that. This is because the
    /// algorithm to determine the gas to forward doesn't account for the gas
    /// overhead between the gas reading and call execution.
    ///
    /// @param hooks The hooks to execute.
    function execute(Hook[] calldata hooks) external onlySettlement {
        // Array bounds and overflow checks are not needed here, as `i` will
        // never overflow and `hooks[i]` will never be out of bounds as `i` is
        // smaller than `hooks.length`.
        unchecked {
            Hook calldata hook;
            for (uint256 i; i < hooks.length; ++i) {
                hook = hooks[i];
                uint256 gasLimit = hook.gasLimit;
                address target = hook.target;
                bytes memory data = hook.callData;

                bool success;
                uint256 gasLeft;
                assembly ("memory-safe") {
                    success := call(gasLimit, target, 0, add(data, 0x20), mload(data), 0, 0)
                    gasLeft := gas()
                }

                // We want to make sure that the previous call was forwarded
                // exactly the gas limit. The remaining gas after the call must
                // then be at least 1/64th of the remaining call by how the
                // CALL opcode forwards its gas. If less gas than expected is
                // found after the call, then it means that the call didn't
                // receive enough gas to be fully executed.
                // For details see the relevant OpenZeppelin code:
                // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/c3961a45380831135b37e55bc3ed441f678a4f5e/contracts/metatx/ERC2771Forwarder.sol#L329-L370
                if (gasLimit > 63 * gasLeft) {
                    assembly ("memory-safe") {
                        invalid()
                    }
                }

                // In order to prevent custom hooks from DoS-ing settlements, we
                // explicitly allow them to revert.
                success;
            }
        }
    }
}
