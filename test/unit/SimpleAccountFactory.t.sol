// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAccountFactory} from "../../src/SimpleAccountFactory.sol";
import {SimpleAccount} from "../../src/SimpleAccount.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

//Test set up for simple account
contract SimpleAccountFactoryTest is Test {
    //Entrypoint needed, same address on all networks
    IEntryPoint entrypoint = IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    address fcOwner = address(0x173);

    function test_getAddress_sameOnDiffChains() public {
        bytes32 salt = bytes32(uint(287555237));
        uint256 accountSalt = 12345;

        SimpleAccountFactory factory = new SimpleAccountFactory{salt: salt}(entrypoint);
        console.log(address(factory));
        console.log(factory.getAddress(address(0x123), accountSalt));
    }

    function test_getAddress_sameAs_CreateAddress() public {
        bytes32 salt = bytes32(uint(287555237));
        uint256 accountSalt = 12345;

        SimpleAccountFactory factory = new SimpleAccountFactory{salt: salt}(entrypoint);
        address predicted = factory.getAddress(address(0x123), accountSalt);

        SimpleAccount account = factory.createAccount(address(0x123), accountSalt);
        
        assertEq(predicted, address(account));
    }
}