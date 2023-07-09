// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8;

import "forge-std/Script.sol";

import {HooksTrampoline} from "../src/HooksTrampoline.sol";

contract DeployHooksTrampoline is Script {
    function run() external returns (HooksTrampoline trampoline) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address settlement = vm.envAddress("SETTLEMENT");
        bytes32 salt = vm.envBytes32("SALT");

        vm.startBroadcast(privateKey);
        trampoline = new HooksTrampoline{salt: salt}(settlement);
        vm.stopBroadcast();
    }
}
