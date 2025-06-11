// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAccountFactory} from "../../src/SimpleAccountFactory.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

//Test set up for simple account
contract SimpleAccountFactoryTest is Test {
    //Entrypoint needed, same address on all networks
    IEntryPoint entrypoint = IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);

    function test_getAddress_sameOnDiffChains() public {
        SimpleAccountFactory factory = new SimpleAccountFactory(entrypoint);
        console.log(factory.getAddress(address(0x123), 12345));
    }
}