// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import {HooksTrampoline} from "../src/HooksTrampoline.sol";

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
        hooks[1] = HooksTrampoline.Hook({
            target: address(reverter),
            callData: abi.encodeCall(Reverter.doRevert, ("boom")),
            gasLimit: 50000
        });
        hooks[2] = HooksTrampoline.Hook({
            target: address(counter),
            callData: abi.encodeCall(Counter.increment, ()),
            gasLimit: 50000
        });

        vm.prank(settlement);
        trampoline.execute(hooks);

        assertEq(counter.value(), 2);
    }

    function test_ExecutesHooksInOrder() public {
        CallInOrder order = new CallInOrder();

        HooksTrampoline.Hook[] memory hooks = new HooksTrampoline.Hook[](10);
        for (uint256 i = 0; i < hooks.length; i++) {
            hooks[i] = HooksTrampoline.Hook({
                target: address(order),
                callData: abi.encodeCall(CallInOrder.called, (i)),
                gasLimit: 25000
            });
        }

        vm.prank(settlement);
        trampoline.execute(hooks);

        assertEq(order.count(), hooks.length);
    }

    function test_HandlesOutOfGas() public {
        Hummer hummer = new Hummer();

        HooksTrampoline.Hook[] memory hooks = new HooksTrampoline.Hook[](1);
        hooks[0] = HooksTrampoline.Hook({
            target: address(hummer),
            callData: abi.encodeCall(Hummer.drive, ()),
            gasLimit: 133700
        });

        vm.prank(settlement);
        uint256 gas = gasleft();
        trampoline.execute(hooks);
        uint256 gasUsed = gas - gasleft();
        uint256 callOverhead = (2600 + 700) * 2; // cold storage access + call cost

        assertApproxEqAbs(gasUsed, hooks[0].gasLimit + callOverhead, 500);
    }

    function test_RevertsWhenNotEnoughGas() public {
        uint256 requiredGas = 100_000;
        BurnGas burner = new BurnGas();

        HooksTrampoline.Hook[] memory hooks = new HooksTrampoline.Hook[](1);
        hooks[0] = HooksTrampoline.Hook({
            target: address(burner),
            callData: abi.encodeCall(BurnGas.consumeAllGas, ()),
            gasLimit: requiredGas
        });

        // Limit the available gas to be less than what the hook requires
        uint256 limitedGas = requiredGas - 1; // 1 gas unit less than required

        vm.prank(settlement);
        vm.expectRevert("Not enough gas");
        trampoline.execute{gas: limitedGas}(hooks);
    }

    function test_RevertsWhenNotEnoughGasForMultipleHooks() public {
        uint256 requiredGas = 100_000;
        BurnGas burner1 = new BurnGas();
        BurnGas burner2 = new BurnGas();

        HooksTrampoline.Hook[] memory hooks = new HooksTrampoline.Hook[](2);
        bytes memory callData = abi.encodeCall(BurnGas.consumeAllGas, ());
        hooks[0] = HooksTrampoline.Hook({target: address(burner1), callData: callData, gasLimit: requiredGas});
        hooks[1] = HooksTrampoline.Hook({target: address(burner2), callData: callData, gasLimit: requiredGas});

        // Limit the available gas to be less than what both hooks require
        uint256 totalRequiredGas = requiredGas * hooks.length;
        uint256 limitedGas = totalRequiredGas - 1; // 1 gas units less than required

        vm.prank(settlement);
        vm.expectRevert("Not enough gas");
        trampoline.execute{gas: limitedGas}(hooks);
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
    function doRevert(string calldata message) external pure {
        revert(message);
    }
}

contract CallInOrder {
    uint256 public count;

    function called(uint256 index) external {
        require(count++ == index, "out of order");
    }
}

contract Hummer {
    function drive() external {
        // Hummers are cars that use way to much gas... Accessing the `n`th
        // memory address past `msize()` (largest accessed memory index)
        // requires paying to 0-out the memory from `msize()` to `n`. This costs
        // 3-gas per 32-bytes at first and grows as `msize()` gets bigger. So
        // accessing the last slot of `type(uint256).max` will use a huge amount
        // of gas. The exact amount is not important for our test. Note that we
        // `sstore()` the read value to prevent the optimizer from optimizing
        // the `mload()` away.
        uint256 n = type(uint256).max;
        assembly {
            sstore(0, mload(n))
        }
    }
}

contract BurnGas {
    function consumeAllGas() public {
        while (true) {
            // Do nothing, just consume gas
        }
    }
}
