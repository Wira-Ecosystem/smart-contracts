// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SimpleAccountV2} from "../src/archived/SimpleAccountV2.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

/** @title UpdateSimpleAccountScript 
 * @notice Example script to deploy an updated version of SimpleAccountV2 contract
 */
contract UpdateSimpleAccountScript is Script {
    function run() external {
        IEntryPoint entrypoint =
            IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);

        vm.startBroadcast(); // Start broadcasting transactions
        SimpleAccountV2 updatedAccount = new SimpleAccountV2(entrypoint, address(0x0));
        vm.stopBroadcast(); // Stop broadcasting transactions
        console.log(address(updatedAccount));
    }
}