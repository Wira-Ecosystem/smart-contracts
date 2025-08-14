// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/SimpleAccountFactory.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

contract WalletAccountFactoryScript is Script {
    function run() external {
        bytes32 salt = bytes32(uint(287555238));
         // Address of the EntryPoint contract on Sepolia (v0.7)
        IEntryPoint ENTRYPOINT =
            IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);

        vm.startBroadcast(); // Start broadcasting transactions
        
        // Initialize the WalletFactory contract
        SimpleAccountFactory walletFactory = new SimpleAccountFactory{salt: salt}(ENTRYPOINT);
        vm.stopBroadcast(); // Stop broadcasting transactions
        console.log(address(walletFactory));
    }
}