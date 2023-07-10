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

    function execute(Hook[] calldata hooks) external onlySettlement {
        // Array bounds and overflow checks are not needed here, as `i` will
        // never overflow and `hooks[i]` will never be out of bounds as `i` is
        // smaller than `hooks.length`.
        unchecked {
            Hook calldata hook;
            for (uint256 i; i < hooks.length; ++i) {
                hook = hooks[i];

                (bool success,) = hook.target.call{gas: hook.gasLimit}(hook.callData);

                // In order to prevent custom hooks from DoS-ing settlements, we
                // explicitely allow them to revert.
                success;
            }
        }
    }
}
