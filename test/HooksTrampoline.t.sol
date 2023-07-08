// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "../src/HooksTrampoline.sol";

contract HooksTrampolineTest is Test {
    address public settlement;
    HooksTrampoline public trampoline;

    function setUp() public {
        settlement = 0x4242424242424242424242424242424242424242;
        trampoline = new HooksTrampoline(settlement);
    }

    function test_RevertsWhenNotCalledFromSettlement() public {
        HooksTrampoline.Hook[] memory hooks;

        vm.expectRevert(HooksTrampoline.NotASettlement.selector);
        trampoline.execute(hooks);
    }

    function test_ExecuteEmptyHooks() public {
        HooksTrampoline.Hook[] memory hooks;

        vm.prank(settlement);
        trampoline.execute(hooks);
    }

    function test_SpecifiesGasLimit() public {
        GasRecorder gas = new GasRecorder();
        uint256 gasLimit = 133700;

        HooksTrampoline.Hook[] memory hooks = new HooksTrampoline.Hook[](1);
        hooks[0] = HooksTrampoline.Hook({
            target: address(gas),
            callData: abi.encodeCall(GasRecorder.record, ()),
            gasLimit: gasLimit
        });

        vm.prank(settlement);
        trampoline.execute(hooks);

        // NOTE: we use a range here, the exact moment we call `gasleft()` is
        // after Solidity runtime setup, so we cannot, in a well-defined way,
        // know the exact amount of gas at this point (it is in theory affected
        // by Solidity compiler optimizations and versions).
        assertApproxEqAbs(gas.value(), gasLimit, 200);
    }

    function test_AllowsReverts() public {
        Counter counter = new Counter();
        Reverter reverter = new Reverter();

        HooksTrampoline.Hook[] memory hooks = new HooksTrampoline.Hook[](3);
        hooks[0] = HooksTrampoline.Hook({
            target: address(counter),
            callData: abi.encodeCall(Counter.increment, ()),
            gasLimit: 50000
        });
        hooks[1] = HooksTrampoline.Hook({target: address(reverter), callData: "", gasLimit: 50000});
        hooks[2] = HooksTrampoline.Hook({
            target: address(counter),
            callData: abi.encodeCall(Counter.increment, ()),
            gasLimit: 50000
        });

        vm.prank(settlement);
        trampoline.execute(hooks);

        assertEq(counter.value(), 2);
    }
}

contract GasRecorder {
    uint256 public value;

    function record() external {
        value = gasleft();
    }
}

contract Counter {
    uint256 public value;

    function increment() external {
        value++;
    }
}

contract Reverter {
    fallback() external {
        revert();
    }
}
