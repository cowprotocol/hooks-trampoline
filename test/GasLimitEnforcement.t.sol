// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {HooksTrampoline} from "../src/HooksTrampoline.sol";

contract GasLimitEnforcementTest is Test {
    address public settlement;
    HooksTrampoline public trampoline;
    GasCraver public gasCraver;

    uint256 constant CRAVED_GAS = 1_000_000;
    /// @dev This constant captures the fact that the trampoline executes a few
    /// operations before calling the desired contract. This means that if we
    /// want to forward some gas to the hook target, the call to the trampoline
    /// also needs to include this extra overhead. The amount is tentative and
    /// depends on the executed call, so it can only be approximately
    /// determined.
    uint256 constant TRAMPOLINE_OVERHEAD = 4_000;
    /// @dev The gas craver contract has some minimal overhead before checking
    /// the gas used in the call. The amount is exact and derived from the
    /// debugger.
    uint256 constant GAS_CRAVER_OVERHEAD = 117;
    /// @dev A bound on how much actual gas is spent when executing the function
    /// in the gas craver contract.
    uint256 constant BOUND_ON_GAS_COST = 60_000;

    /// @dev When a function is called, only part of the gas is forwarded to the
    /// called contract. Since we're testing gas amounts, we want to make sure
    /// all calls in the tests are being given more than enough gas to be called
    /// with the amount of gas specified in the call (`call{gas: ...}`).
    modifier gasPadded() {
        _;
        // This require statement is here to make the test gas estimation use
        // a larger gas limit than needed for executing the test. We assume that
        // the calls in the test will use less than the amount of gas in the
        // right-hand side of the inequality.
        require(gasleft() > 42 * CRAVED_GAS, "Foundry gas estimation failed");
    }

    function setUp() public {
        settlement = 0x4242424242424242424242424242424242424242;
        trampoline = new HooksTrampoline(settlement);
        gasCraver = new GasCraver(CRAVED_GAS);
    }

    function test_GasCraverDirectExecutionSuccess() public gasPadded {
        // WHEN: we call the gasCraver with the call overhead
        gasCraver.foo{gas: CRAVED_GAS + GAS_CRAVER_OVERHEAD}();

        // THEN: the gasCraver should succeed
        assertEq(gasCraver.stateChanged(), true);
    }

    function test_GasCraverDirectExecutionFailure() public gasPadded {
        // WHEN: we call the gasCraver without call overhead
        vm.expectRevert("I want more gas");
        gasCraver.foo{gas: CRAVED_GAS}();

        // THEN: the gasCraver should fail
        assertEq(gasCraver.stateChanged(), false);
    }

    function test_TrampolineWithSufficientGas() public gasPadded {
        // GIVEN: a hook with a gasLimit that includes the call overhead
        HooksTrampoline.Hook[] memory hooks = createHook(CRAVED_GAS + GAS_CRAVER_OVERHEAD);

        // WHEN: we execute the trampoline with double the call overhead
        vm.prank(settlement);
        trampoline.execute{gas: limitForForwarding(CRAVED_GAS + GAS_CRAVER_OVERHEAD)}(hooks);

        // THEN: the gasCraver should succeed
        assertEq(gasCraver.stateChanged(), true, "Hook should execute successfully");
    }

    function test_TrampolineWithInsufficientHookGasLimit() public gasPadded {
        // GIVEN: a hook with a gasLimit that is less than the extra gas
        HooksTrampoline.Hook[] memory hooks = createHook(CRAVED_GAS - GAS_CRAVER_OVERHEAD);

        // WHEN: we execute the trampoline with the extra gas
        vm.prank(settlement);
        trampoline.execute{gas: limitForForwarding(CRAVED_GAS + GAS_CRAVER_OVERHEAD)}(hooks);

        // THEN: the gasCraver should fail
        assertEq(gasCraver.stateChanged(), false, "Hook should fail due to insufficient gas limit");
    }

    function test_TrampolineWithInsufficientAvailableGas() public gasPadded {
        // GIVEN: a hook with a gasLimit that includes the extra gas
        HooksTrampoline.Hook[] memory hooks = createHook(CRAVED_GAS + GAS_CRAVER_OVERHEAD);

        // WHEN: we execute the trampoline without the extra gas
        // THEN: the it should revert with NotEnoughGas
        vm.prank(settlement);
        vm.expectRevert(HooksTrampoline.NotEnoughGas.selector);
        trampoline.execute{gas: limitForForwarding(CRAVED_GAS + GAS_CRAVER_OVERHEAD) - TRAMPOLINE_OVERHEAD}(hooks);

        // THEN: the gasCraver should not execute
        assertEq(gasCraver.stateChanged(), false, "Hook should not execute");
    }

    /// @dev This test shows an undesired behavior of the trampoline contract.
    /// It comes from the fact that we can't exactly say in the trampoline how
    /// much gas is forwarded in the call exactly and so it can't enforce that
    /// the amount in the call is exactly the desired amount. This is visible
    /// in the following test, where ideally the trampoline execution would
    /// revert.
    /// If this test reverts, try to adjust the critical amount, the valid range
    /// at the time of writing is ~500 < criticalAmount < ~3000.
    function test_undesiredBehavior_TrampolineWithInsufficientAvailableGas() public gasPadded {
        uint256 criticalAmount = 3000;

        // GIVEN: a hook with a gasLimit that includes the call overhead
        HooksTrampoline.Hook[] memory hooks = createHook(CRAVED_GAS + GAS_CRAVER_OVERHEAD);

        // WHEN: we execute the trampoline without the call overhead
        // THEN: it (surprisingly) succeeds
        vm.prank(settlement);
        trampoline.execute{gas: limitForForwarding(CRAVED_GAS + GAS_CRAVER_OVERHEAD) - criticalAmount}(hooks);

        // THEN: despite that, the gasCraver does not execute
        assertEq(gasCraver.stateChanged(), false, "Hook does not execute");
    }

    function test_TrampolineGasEfficiency() public gasPadded {
        // GIVEN: a hook with a gasLimit that includes the call overhead
        HooksTrampoline.Hook[] memory hooks = createHook(CRAVED_GAS + GAS_CRAVER_OVERHEAD);

        // WHEN: we execute the trampoline with double the call overhead
        vm.prank(settlement);
        uint256 gasMetering = gasleft();
        trampoline.execute{gas: limitForForwarding(CRAVED_GAS + GAS_CRAVER_OVERHEAD)}(hooks);
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

    /// @dev The CALL opcode forwards at most 63/64th of the gas left, meaning
    /// that if we want to forward `gas` in a trampolined call then we need to
    /// account for that. Also, before the trampolined call the trampoline
    /// contract execute extra operations that have their own overhead.
    function limitForForwarding(uint256 gas) private pure returns (uint256) {
        return (gas + TRAMPOLINE_OVERHEAD) * 64 / 63;
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
