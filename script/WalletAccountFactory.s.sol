// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/SimpleAccountFactory.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

contract WalletAccountFactoryScript is Script {
    // Address of the EntryPoint contract on Sepolia (v0.7)
    IEntryPoint constant ENTRYPOINT =
        IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // Fetch the private key from environment variables
        address tokenPaymaster = vm.envAddress("TOKEN_PAYMASTER");
        bytes32 salt = bytes32(uint(287555237));

        vm.startBroadcast(deployerPrivateKey); // Start broadcasting transactions
        
        // Initialize the WalletFactory contract
        SimpleAccountFactory walletFactory = new SimpleAccountFactory{salt: salt}();
        walletFactory.initialize(ENTRYPOINT, tokenPaymaster);
        console.log(address(walletFactory));

        vm.stopBroadcast(); // Stop broadcasting transactions
    }
}