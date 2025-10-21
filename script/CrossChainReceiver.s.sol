// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CrossChainReceiver} from "../src/archived/transferer/CrossChainReceiver.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

contract CrossChainReceiverScript is Script {
	// Address of the EntryPoint contract on Sepolia (v0.7)
    IEntryPoint constant ENTRYPOINT =
        IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
	//Wormhole contracts
    mapping(uint256 => address) private cores;
    mapping(uint256 => address) private relayers;
    mapping(uint256 => address) private bridges;
    mapping(uint256 => address) private gasTokens;

	function run() external {
		uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // Fetch the private key from environment variables

        //Wormhole OP sepolia contracts
        cores[11155420] = 0x31377888146f3253211EFEf5c676D41ECe7D58Fe;
        relayers[11155420] = 0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE;
        bridges[11155420] = 0x99737Ec4B815d816c49A385943baf0380e75c0Ac;

        //Wormhole Polygon Amoy contracts
        cores[80002] = 0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35;
        relayers[80002] = 0x362fca37E45fe1096b42021b543f462D49a5C8df;
        bridges[80002] = 0xC7A204bDBFe983FCD8d8E61D02b475D4073fF97e;

        //Wormhole Base Sepolia contracts
        cores[84532] = 0x79A1027a6A159502049F10906D333EC57E95F083;
        relayers[84532] = 0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE;
        bridges[84532] = 0x86F55A04690fd7815A3D802bD587e83eA888B239;

        //Wormhole Arbitrum Sepolia contracts
        cores[421614] = 0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35;
        relayers[421614] = 0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470;
        bridges[421614] = 0xC7A204bDBFe983FCD8d8E61D02b475D4073fF97e;

        require(cores[block.chainid] != address(0), "Chain not supported");

		vm.startBroadcast(deployerPrivateKey);

		CrossChainReceiver r = new CrossChainReceiver(
			relayers[block.chainid],
            bridges[block.chainid],
            cores[block.chainid]
		);
        console.log("CrossChainReceiver deployed at:", address(r));

		vm.stopBroadcast();
	}
}