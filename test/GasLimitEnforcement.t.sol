// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import {HooksTrampoline} from "../src/HooksTrampoline.sol";

import {console} from "forge-std/console.sol";

contract GasLimitEnforcementTest is Test {
    address public settlement;
    HooksTrampoline public trampoline;
    GasCraver public gasCraver;

    uint256 constant CRAVED_GAS = 1_000_000;
    uint256 constant EXTRA_GAS = 12_000;
    uint256 constant BOUND_ON_GAS_COST = 60_000;

    function setUp() public {
        settlement = 0x4242424242424242424242424242424242424242;
        trampoline = new HooksTrampoline(settlement);
        gasCraver = new GasCraver(CRAVED_GAS);
    }

    function test_GasCraverDirectExecutionSuccess() public {
        // WHEN: we call the gasCraver with the extra gas
        gasCraver.foo{gas: CRAVED_GAS + EXTRA_GAS}();

        // THEN: the gasCraver should succeed
        assertEq(gasCraver.stateChanged(), true);
    }

    function test_GasCraverDirectExecutionFailure() public {
        // WHEN: we call the gasCraver without extra gas
        vm.expectRevert("I want more gas");
        gasCraver.foo{gas: CRAVED_GAS}();

        // THEN: the gasCraver should fail
        assertEq(gasCraver.stateChanged(), false);
    }

    function test_TrampolineWithSufficientGas() public {
        // GIVEN: a hook with a gasLimit that includes the extra gas
        HooksTrampoline.Hook[] memory hooks = createHook(CRAVED_GAS + EXTRA_GAS);

        // WHEN: we execute the trampoline with double the extra gas
        vm.prank(settlement);
        trampoline.execute{gas: CRAVED_GAS + 2 * EXTRA_GAS}(hooks);

        // THEN: the gasCraver should succeed
        assertEq(gasCraver.stateChanged(), true, "Hook should execute successfully");
    }

    function test_TrampolineWithInsufficientHookGasLimit() public {
        // GIVEN: a hook with a gasLimit that is less than the extra gas
        HooksTrampoline.Hook[] memory hooks = createHook(CRAVED_GAS - EXTRA_GAS);

        // WHEN: we execute the trampoline with the extra gas
        vm.prank(settlement);
        trampoline.execute{gas: CRAVED_GAS + EXTRA_GAS}(hooks);

        // THEN: the gasCraver should fail
        assertEq(gasCraver.stateChanged(), false, "Hook should fail due to insufficient gas limit");
    }

    function test_TrampolineWithInsufficientAvailableGas() public {
        // GIVEN: a hook with a gasLimit that includes the extra gas
        HooksTrampoline.Hook[] memory hooks = createHook(CRAVED_GAS + EXTRA_GAS);

        // WHEN: we execute the trampoline without the extra gas
        // THEN: the it should revert with NotEnoughGas
        vm.prank(settlement);
        vm.expectRevert(HooksTrampoline.NotEnoughGas.selector);
        trampoline.execute{gas: CRAVED_GAS - EXTRA_GAS}(hooks);

        // THEN: the gasCraver should not execute
        assertEq(gasCraver.stateChanged(), false, "Hook should not execute");
    }

    function test_TrampolineGasEfficiency() public {
        // GIVEN: a hook with a gasLimit that includes the extra gas
        HooksTrampoline.Hook[] memory hooks = createHook(CRAVED_GAS + EXTRA_GAS);

        // WHEN: we execute the trampoline with double the extra gas
        vm.prank(settlement);
        uint256 gasMetering = gasleft();
        trampoline.execute{gas: CRAVED_GAS + 2 * EXTRA_GAS}(hooks);
        gasMetering -= gasleft();

        // THEN: the gasCraver should execute
        assertEq(gasCraver.stateChanged(), true, "Hook should execute successfully");

        // THEN: the gas consumed should be reasonable
        assertLt(gasMetering, BOUND_ON_GAS_COST, "Trampoline should be gas efficient");
    }

    // Helper function to create a hook
    function createHook(uint256 gasLimit) internal view returns (HooksTrampoline.Hook[] memory) {
        HooksTrampoline.Hook[] memory hooks = new HooksTrampoline.Hook[](1);
        hooks[0] = HooksTrampoline.Hook({
            target: address(gasCraver),
            callData: abi.encodeCall(GasCraver.foo, ()),
            gasLimit: gasLimit
        });
        return hooks;
    }

    // This test demonstrates that Solidity calls reserve 1/64th of available gas
    // and the called contract receives less gas than what was specified.
    //
    // This is important because it means we need to account for this reservation
    // when setting gas limits for hooks, otherwise they may fail unexpectedly.
    function test_DemonstratesOneSixtyFourthGasReservation() public {
        GasRecorder gasRecorder = new GasRecorder();

        // Use a large gas limit to make the 1/64th reservation more noticeable
        uint256 largeGasLimit = 10_000_000; // 10M gas
        uint256 expectedReservation = largeGasLimit / 64; // Expected gas reservation 1/64th of the gas limit

        HooksTrampoline.Hook[] memory hooks = new HooksTrampoline.Hook[](1);
        hooks[0] = HooksTrampoline.Hook({
            target: address(gasRecorder),
            callData: abi.encodeCall(GasRecorder.record, ()),
            gasLimit: largeGasLimit - expectedReservation
        });

        vm.prank(settlement);
        trampoline.execute{gas: largeGasLimit}(hooks);

        uint256 actualGasReceived = gasRecorder.value();
        uint256 expectedGasReceived = largeGasLimit - expectedReservation;

        // The actual gas received should be similar to the expected
        assertApproxEqAbs(actualGasReceived, expectedGasReceived, 6000);

        emit log_named_uint("TX gas limit", largeGasLimit);
        emit log_named_uint("Actual gas received", actualGasReceived);
        emit log_named_uint("Expected gas received", expectedGasReceived);
    }
}

contract GasCraver {
    uint256 immutable gasLimit;
    bool public stateChanged = false;

    constructor(uint256 _gasLimit) {
        gasLimit = _gasLimit;
    }

    function foo() external {
        uint256 gas = gasleft();
        require(gas > gasLimit, "I want more gas");
        stateChanged = true;
    }

    function reset() external {
        stateChanged = false;
    }
}

contract GasRecorder {
    uint256 public value;

    function record() external {
        value = gasleft();
    }
}
