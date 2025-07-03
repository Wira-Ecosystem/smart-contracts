// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAccount} from "../../src/SimpleAccount.sol";
import {SimpleAccountFactory} from "../../src/SimpleAccountFactory.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

//Test set up for simple account
contract SimpleAccountTest is Test {
    //Entrypoint needed, same address on all networks
    IEntryPoint entrypoint = IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    //Factory to create new SimpleAccounts
    SimpleAccountFactory factory;

    function setUp() public {
        address fcOwner = address(0x173);
        factory = new SimpleAccountFactory(entrypoint, fcOwner);
        //initialize with entrypoint and fake tokenPaymaster
        vm.prank(fcOwner);
        factory.initialize(address(0x789));
    }

    function test_GetDeposit() public {
        //Create a new account with the factory, an owner and a random salt
        SimpleAccount acc = factory.createAccount(msg.sender, 123456);

        //Reading calls are simple
        uint deposit = acc.getDeposit();
        assertEq(deposit, 0);
    }

    function test_SetCollectOnDeliverDirectly() public {
        //for onlyOwner calls, startPrank is needed
        vm.startPrank(address(0x123));
        SimpleAccount acc = factory.createAccount(address(0x123), 123456);

        assertEq(acc.letCollectOnDeliver(), false);
        //direct call is possible, but not usual
        acc.setCollectOnDeliver(true);
        assertEq(acc.letCollectOnDeliver(), true);
        vm.stopPrank();
    }

    function test_SetCollectOnDeliverByOwner() public {
        vm.startPrank(address(0x123));
        SimpleAccount acc = factory.createAccount(address(0x123), 123456);

        assertEq(acc.letCollectOnDeliver(), false);

        //encode the function and the parameter
        bytes memory func = abi.encodeWithSignature("setCollectOnDeliver(bool)", true);
        //call execute with the same contract address, 0 value, and the encoded func
        acc.execute(address(acc), 0, func);

        assertEq(acc.letCollectOnDeliver(), true);
        vm.stopPrank();
    }

    function test_SetCollectOnDeliverByEntrypoint() public {
        vm.startPrank(address(0x123));
        SimpleAccount acc = factory.createAccount(address(0x123), 123456);
        vm.stopPrank();

        //call function as entrypoint
        vm.startPrank(address(entrypoint));
        assertEq(acc.letCollectOnDeliver(), false);

        bytes memory func = abi.encodeWithSignature("setCollectOnDeliver(bool)", true);
        acc.execute(address(acc), 0, func);

        assertEq(acc.letCollectOnDeliver(), true);
        vm.stopPrank();
    }

    function test_SetCollectOnDeliverByStrange() public {
        vm.startPrank(address(0x123));
        SimpleAccount acc = factory.createAccount(address(0x123), 123456);
        vm.stopPrank();

        //extrange try to call account function
        vm.startPrank(address(0x456));
        assertEq(acc.letCollectOnDeliver(), false);

        bytes memory func = abi.encodeWithSignature("setCollectOnDeliver(bool)", true);
        vm.expectRevert();
        acc.execute(address(acc), 0, func);

        assertEq(acc.letCollectOnDeliver(), false);
        vm.stopPrank();
    }

    function test_AddDeposit() public {
        address owner = vm.addr(0x123);
        SimpleAccount acc = factory.createAccount(owner, 123456);

        //To call a payable function through execute, account and not owner must have funds
        vm.deal(address(acc), 1 ether);
        vm.startPrank(owner);

        assertEq(acc.getDeposit(), 0);
        bytes memory func = abi.encodeWithSignature("addDeposit()");
        acc.execute(address(acc), 0.01 ether, func);
        assertEq(acc.getDeposit(), 0.01 ether);

        vm.stopPrank();        
    }

    function test_AddDepositWithoutFunds() public {
        address owner = vm.addr(0x123);
        SimpleAccount acc = factory.createAccount(owner, 123456);

        vm.startPrank(owner);

        assertEq(acc.getDeposit(), 0);
        bytes memory func = abi.encodeWithSignature("addDeposit()");

        vm.expectRevert();
        acc.execute(address(acc), 0.01 ether, func);

        assertEq(acc.getDeposit(), 0);
        vm.stopPrank();        
    }

    function test_AddDepositWithOwnerFunds() public {
        address owner = vm.addr(0x123);
        vm.deal(owner, 1 ether);

        SimpleAccount acc = factory.createAccount(owner, 123456);

        vm.startPrank(owner);
        assertEq(acc.getDeposit(), 0);
        bytes memory func = abi.encodeWithSignature("addDeposit()");

        vm.expectRevert();
        acc.execute(address(acc), 0.01 ether, func);

        assertEq(acc.getDeposit(), 0);
        vm.stopPrank();        
    }

    function test_withdrawDepositTo() public {
        address payable owner = payable(vm.addr(0x123));
        SimpleAccount acc = fundAccountDeposit(owner);
        address receiver = vm.addr(0x456);

        vm.startPrank(owner);
        bytes memory func = abi.encodeWithSignature("withdrawDepositTo(address,uint256)", receiver, 0.01 ether);
        acc.execute(address(acc), 0, func);
        vm.stopPrank();

        assertEq(receiver.balance, 0.01 ether);
    }

    function fundAccountDeposit(address owner) internal returns(SimpleAccount) {
        SimpleAccount acc = factory.createAccount(owner, 123456);

        vm.deal(address(acc), 1 ether);
        vm.startPrank(owner);

        assertEq(acc.getDeposit(), 0);
        bytes memory func = abi.encodeWithSignature("addDeposit()");
        acc.execute(address(acc), 0.01 ether, func);
        assertEq(acc.getDeposit(), 0.01 ether);

        vm.stopPrank();
        return acc;
    }
}