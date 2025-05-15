// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/SimpleAccountFactory.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

contract WalletAccountFactoryScript is Script {
    // Address of the EntryPoint contract on Sepolia (v0.7)
    IEntryPoint constant ENTRYPOINT =
        IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // Fetch the private key from environment variables
        vm.startBroadcast(deployerPrivateKey); // Start broadcasting transactions
        
        SimpleAccountFactory walletFactory = new SimpleAccountFactory(ENTRYPOINT); // Initialize the WalletFactory contract
        console.log(address(walletFactory));

        vm.stopBroadcast(); // Stop broadcasting transactions
    }
}