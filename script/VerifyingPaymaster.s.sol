// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/VerifyingPaymaster.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

contract VerifyingPaymasterScript is Script {
    // Address of the EntryPoint contract on Sepolia (v0.7)
    IEntryPoint constant ENTRYPOINT =
        IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);

    function run() external {
        address verifierSigner = vm.envAddress("VERIFIER_ADDRESS"); // Fetch the paymaster verifier service signer from env variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // Fetch the private key from environment variables
        vm.startBroadcast(deployerPrivateKey); // Start broadcasting transactions
        
        VerifyingPaymaster verifyingPaymaster = new VerifyingPaymaster(ENTRYPOINT, verifierSigner); // Initialize the VerifyingPaymaster contract
        console.log(address(verifyingPaymaster));

        vm.stopBroadcast(); // Stop broadcasting transactions
    }
}