// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.7;

import {Script} from "forge-std/Script.sol";
import {Milkman} from "src/Milkman.sol";

/// @title Deployer Script for the Milkman contract.
/// @author CoW Swap Developers.
contract DeployStandaloneMilkman is Script {
    function run() external {
        vm.startBroadcast();

        new Milkman();

        vm.stopBroadcast();
    }
}
