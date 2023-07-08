// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8;

contract HooksTrampoline {
    struct Hook {
        address target;
        bytes callData;
        uint256 gasLimit;
    }

    error NotASettlement();

    address public immutable settlement;

    constructor(address settlement_) {
        settlement = settlement_;
    }

    modifier onlySettlement() {
        if (msg.sender != settlement) {
            revert NotASettlement();
        }
        _;
    }

    function execute(Hook[] calldata) external onlySettlement {
        // Assembly is used to efficiently iterate over the ABI-encoded hooks
        // and do inner calls.
        assembly {
            let ptr := mload(0x40)

            let hooks := add(calldataload(0x4), 0x4)
            let len := shl(5, calldataload(hooks))

            hooks := add(hooks, 0x20)
            for { let i := 0 } lt(i, len) { i := add(i, 0x20) } {
                let hook := add(calldataload(add(hooks, i)), hooks)
                let data := add(calldataload(add(hook, 0x20)), hook)
                calldatacopy(ptr, add(data, 0x20), calldataload(data))

                // In order to prevent custom hooks from DoS-ing settlements, we
                // explicitely allow them to revert.
                pop(call(calldataload(add(hook, 0x40)), calldataload(hook), 0, ptr, calldataload(data), 0, 0))
            }
        }

        // Partial assembly implementation
        /*
        unchecked {
            Hook calldata hook;

            address target;
            bytes calldata callData;
            uint256 gasLimit;

            for (uint256 i; i < hooks.length; ++i) {
                hook = hooks[i];

                target = hook.target;
                callData = hook.callData;
                gasLimit = hook.gasLimit;

                // In order to prevent custom hooks from DoS-ing settlements, we
                // explicitely allow them to revert.
                assembly {
                    let ptr := mload(0x40)
                    calldatacopy(ptr, callData.offset, callData.length)
                    pop(call(gasLimit, target, 0, ptr, callData.length, 0, 0))
                }
            }
        }
        */
    }
}
