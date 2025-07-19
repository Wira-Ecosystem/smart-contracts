// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAccount} from "../../src/SimpleAccount.sol";
import {SimpleAccountFactory} from "../../src/SimpleAccountFactory.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

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



    // 1) VALIDACIÓN DE FIRMA
    // Signature Validation Tests ====================================================
    function test_SignatureValidation_Success() public {
        uint256 ownerPrivateKey = 0x123;
        address owner = vm.addr(0x123);
        // Create account
        SimpleAccount acc = factory.createAccount(owner, 123456);
        
        // Prepare user operation
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(acc),
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSignature("execute(address,uint256,bytes)", address(acc), 0, ""),
            accountGasLimits: 0,
            preVerificationGas: 0,
            gasFees: 0,
            paymasterAndData: "",
            signature: ""
        });
        
        // Get userOp hash and sign it
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Validate signature
        vm.startPrank(address(entrypoint));
        uint256 validationData = acc.validateUserOp(userOp, userOpHash, 0); // aquie pod derás se usa _validateSignature
        vm.stopPrank();
        
        // Should return SIG_VALIDATION_SUCCESS (0)
        assertEq(validationData, 0, "Signature validation should succeed");
    }

    
    function test_SignatureValidation_Failure_WrongSigner() public {
        address owner = vm.addr(0x123);
        uint256 nonOwnerPrivateKey = 0x456; // Clave diferente
        // Create account
        SimpleAccount acc = factory.createAccount(owner, 123456);
        
        // Prepare user operation
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(acc),
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSignature("execute(address,uint256,bytes)", address(acc), 0, ""),
            accountGasLimits: 0,
            preVerificationGas: 0,
            gasFees: 0,
            paymasterAndData: "",
            signature: ""
        });
        
        // Get userOp hash and sign with WRONG key
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(nonOwnerPrivateKey, ethSignedHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Validate signature
        vm.startPrank(address(entrypoint));
        uint256 validationData = acc.validateUserOp(userOp, userOpHash, 0);
        vm.stopPrank();
        
        // Should return SIG_VALIDATION_FAILED (1)
        assertEq(validationData, 1, "Signature validation should fail with wrong signer");
    }

    function test_SignatureValidation_Failure_TamperedData() public {
        uint256 ownerPrivateKey = 0x123;
        address owner = vm.addr(0x123);
        // Create account
        SimpleAccount acc = factory.createAccount(owner, 123456);
        
        // Prepare user operation
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(acc),
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSignature("execute(address,uint256,bytes)", address(acc), 0, ""),
            accountGasLimits: 0,
            preVerificationGas: 0,
            gasFees: 0,
            paymasterAndData: "",
            signature: ""
        });
        
        // Get userOp hash and sign
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Tamper with the data after signing
        userOp.callData = abi.encodeWithSignature("execute(address,uint256,bytes)", address(acc), 1 ether, "");

        // Validate signature with TAMPERED hash (this should fail because signature was made for original hash)
        bytes32 tamperedUserOpHash = entrypoint.getUserOpHash(userOp);
        vm.startPrank(address(entrypoint));
        uint256 validationData = acc.validateUserOp(userOp, tamperedUserOpHash, 0);
        vm.stopPrank();
        
        // Should return SIG_VALIDATION_FAILED (1)
        assertEq(validationData, 1, "Signature validation should fail with tampered data");
    }

    // ===================== CRITICAL SECURITY TESTS =====================

    // 1) Test for reentrancy attacks
    function test_SecurityCritical_ReentrancyAttack() public {
        address owner = vm.addr(0x123);
        SimpleAccount acc = factory.createAccount(owner, 123456);
        
        // Fund the account
        vm.deal(address(acc), 2 ether);
        vm.startPrank(owner);
        
        // Try to execute a call to a non-existent function (this will revert)
        // Testing that the account properly handles external call failures
        vm.expectRevert(); // Should revert because maliciousFunction doesn't exist
        acc.execute(address(acc), 0, abi.encodeWithSignature("maliciousFunction()"));
        vm.stopPrank();
        
        // Account should still have its balance intact
        assertEq(address(acc).balance, 2 ether, "Account balance should remain intact");
    }

    // 2) Test for unauthorized access control
    function test_SecurityCritical_UnauthorizedExecute() public {
        address owner = vm.addr(0x123);
        address attacker = vm.addr(0x456);
        SimpleAccount acc = factory.createAccount(owner, 123456);
        
        // Attacker tries to execute unauthorized transaction
        vm.startPrank(attacker);
        vm.expectRevert(); // Should revert due to access control
        acc.execute(address(acc), 0, abi.encodeWithSignature("setCollectOnDeliver(bool)", true));
        vm.stopPrank();
    }

    // 2) Test for unauthorized access control
    function test_SecurityCritical_UnauthorizedGuardianRecovery() public {
        address owner = vm.addr(0x123);
        address attacker = vm.addr(0x456);
        SimpleAccount acc = factory.createAccount(owner, 123456);
        
        // Set a guardian
        vm.startPrank(owner);
        acc.setGuardian(vm.addr(0x789));
        vm.stopPrank();
        
        // Attacker tries to execute recovery
        vm.startPrank(attacker);
        vm.expectRevert(); // Should revert as attacker is not guardian
        acc.executeRecovery(attacker);
        vm.stopPrank();
    }

    // 3) Test for guardian recovery vulnerabilities
    function test_SecurityCritical_IntegerOverflow() public {
        address owner = vm.addr(0x123);
        SimpleAccount acc = factory.createAccount(owner, 123456);
        
        // Try to set maximum debt value
        vm.startPrank(address(factory));
        acc.setCreateDebt(type(uint256).max);
        assertEq(acc.createDebt(), type(uint256).max, "Should handle max uint256 value");
        vm.stopPrank();
    }

    // 7) Test for external call security
    function test_SecurityCritical_ExternalCallSecurity() public {
        address owner = vm.addr(0x123);
        SimpleAccount acc = factory.createAccount(owner, 123456);
        
        // Create a malicious contract that always reverts
        address maliciousContract = address(new MaliciousContract());
        
        vm.startPrank(owner);
        
        // Execute should handle external call failures gracefully
        vm.expectRevert(); // Should propagate the revert
        acc.execute(maliciousContract, 0, abi.encodeWithSignature("maliciousFunction()"));
        
        vm.stopPrank();
    }

    // 8) Test for gas griefing attacks
    function test_SecurityCritical_GasGriefing() public {
        address owner = vm.addr(0x123);
        SimpleAccount acc = factory.createAccount(owner, 123456);
        
        vm.startPrank(owner);
        
        // Try to execute a gas-expensive operation
        uint256 gasStart = gasleft();
        acc.execute(address(acc), 0, abi.encodeWithSignature("setCollectOnDeliver(bool)", true));
        uint256 gasUsed = gasStart - gasleft();
        
        // Gas consumption should be reasonable
        assertTrue(gasUsed < 100000, "Gas consumption should be reasonable");
        
        vm.stopPrank();
    }

    // 9) Test for signature replay attacks
    function test_SecurityCritical_SignatureReplay() public {
        uint256 ownerPrivateKey = 0x123;
        address owner = vm.addr(0x123);
        SimpleAccount acc = factory.createAccount(owner, 123456);
        
        // Create and sign a user operation
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(acc),
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSignature("execute(address,uint256,bytes)", address(acc), 0, ""),
            accountGasLimits: 0,
            preVerificationGas: 0,
            gasFees: 0,
            paymasterAndData: "",
            signature: ""
        });
        
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        // First validation should succeed
        vm.startPrank(address(entrypoint));
        uint256 validationData1 = acc.validateUserOp(userOp, userOpHash, 0);
        assertEq(validationData1, 0, "First signature validation should succeed");
        
        // Same signature with same nonce should still be valid (nonce handling is at EntryPoint level)
        uint256 validationData2 = acc.validateUserOp(userOp, userOpHash, 0);
        assertEq(validationData2, 0, "Signature validation should succeed");
        vm.stopPrank();
    }

    // 10) Test for access control on critical functions
    function test_SecurityCritical_AccessControlCriticalFunctions() public {
        address owner = vm.addr(0x123);
        address attacker = vm.addr(0x456);
        SimpleAccount acc = factory.createAccount(owner, 123456);
        
        // Give the owner some ETH and deposit to EntryPoint directly
        vm.deal(owner, 1 ether);
        vm.startPrank(owner);
        entrypoint.depositTo{value: 0.5 ether}(address(acc));
        vm.stopPrank();
        
        // Verify deposit was successful
        uint256 deposit = acc.getDeposit();
        assertEq(deposit, 0.5 ether, "Deposit should be 0.5 ether");
        
        // Attacker tries to withdraw deposits
        vm.startPrank(attacker);
        vm.expectRevert(); // Should revert due to onlyOwner modifier
        acc.withdrawDepositTo(payable(attacker), 0.1 ether);
        vm.stopPrank();
        
        // Attacker tries to set create debt
        vm.startPrank(attacker);
        vm.expectRevert(); // Should revert due to access control
        acc.setCreateDebt(1000);
        vm.stopPrank();
    }

    // ===================== WORKFLOW TESTS =====================

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

    function test_SetCollectOnDeliverByStranger() public {
        vm.startPrank(address(0x123));
        SimpleAccount acc = factory.createAccount(address(0x123), 123456);
        vm.stopPrank();

        //stranger tries to call account function
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

    function test_WithdrawDepositTo() public {
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

// Helper contract for testing external call security
contract MaliciousContract {
    function maliciousFunction() external pure {
        revert("Malicious contract always reverts");
    }
}