// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/SimpleAccountFactory.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

contract WalletAccountFactoryScript is Script {
    // Address of the EntryPoint contract on Sepolia (v0.8)
    IEntryPoint constant ENTRYPOINT =
        IEntryPoint(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // Fetch the private key from environment variables
        vm.startBroadcast(deployerPrivateKey); // Start broadcasting transactions
        
        SimpleAccountFactory walletFactory = new SimpleAccountFactory(ENTRYPOINT); // Initialize the WalletFactory contract
        console.log(address(walletFactory));

        vm.stopBroadcast(); // Stop broadcasting transactions
    }
}