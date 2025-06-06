// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/interfaces/PackedUserOperation.sol";
import {VerifyingPaymaster} from "../../src/VerifyingPaymaster.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract VerifyingPaymasterTest is Test {
    IEntryPoint public immutable entrypoint = IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    PackedUserOperation public testUserOp = PackedUserOperation({
        sender: address(0x123),
        nonce: 1,
        initCode: hex"636F6E7374727563746F722875696E7429",
        callData: hex"65786563757465286279746573206461746129",
        accountGasLimits: bytes32("7D0"),
        preVerificationGas: 1_000,
        gasFees: bytes32("2710"),
        paymasterAndData: hex"68D985441429561E1d8eb9274A0483462B229FBb",
        signature: hex"8B89386EA80D89"
    });

    function test_constructorSuccess() public {
        address verifyingSigner = address(0x123);
        new VerifyingPaymaster(entrypoint, verifyingSigner);
    }

    function test_getHast_success() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);
        v.getHash(testUserOp, 0, 0);
    }

    function test_getHash_sameHashWithSameData() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        bytes32 originalHash = v.getHash(testUserOp, 300, 200);
        bytes32 secondHash = v.getHash(testUserOp, 300, 200);

        assertEq(originalHash, secondHash);
    }

    function test_getHash_changeHashOn_validUntil() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        bytes32 originalHash = v.getHash(testUserOp, 300, 200);
        bytes32 modifiedHash = v.getHash(testUserOp, 301, 200);

        assertEq(originalHash != modifiedHash, true);
    }

    function test_getHash_changeHashOn_validAfter() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        bytes32 originalHash = v.getHash(testUserOp, 300, 200);
        bytes32 modifiedHash = v.getHash(testUserOp, 300, 201);

        assertEq(originalHash != modifiedHash, true);
    }

    function test_getHash_changeHashOn_sender() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.sender = address(0x124);

        bytes32 originalHash = v.getHash(testUserOp, 300, 200);
        bytes32 modifiedHash = v.getHash(modifiedUserOp, 300, 200);

        assertEq(originalHash != modifiedHash, true);
    }

    function test_getHash_changeHashOn_nonce() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.nonce = 2;

        bytes32 originalHash = v.getHash(testUserOp, 300, 200);
        bytes32 modifiedHash = v.getHash(modifiedUserOp, 300, 200);

        assertEq(originalHash != modifiedHash, true);
    }

    function test_getHash_changeHashOn_initCode() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.initCode = hex"636F6E7374727563746F722875696E7428"; //modify last character

        bytes32 originalHash = v.getHash(testUserOp, 300, 200);
        bytes32 modifiedHash = v.getHash(modifiedUserOp, 300, 200);

        assertEq(originalHash != modifiedHash, true);
    }

    function test_getHash_changeHashOn_callData() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.callData = hex"65786563757465286279746573206461746128"; //modify last character

        bytes32 originalHash = v.getHash(testUserOp, 300, 200);
        bytes32 modifiedHash = v.getHash(modifiedUserOp, 300, 200);

        assertEq(originalHash != modifiedHash, true);
    }


    function test_getHash_sameHashOn_accountGasLimits() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.accountGasLimits = bytes32("3E0");

        bytes32 originalHash = v.getHash(testUserOp, 300, 200);
        bytes32 modifiedHash = v.getHash(modifiedUserOp, 300, 200);

        assertEq(originalHash, modifiedHash);
    }

    function test_getHash_changeHashOn_preVerificationGas() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.preVerificationGas = 1_001;

        bytes32 originalHash = v.getHash(testUserOp, 300, 200);
        bytes32 modifiedHash = v.getHash(modifiedUserOp, 300, 200);

        assertEq(originalHash != modifiedHash, true);
    }

    function test_getHash_sameHashOn_gasFees() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.gasFees = bytes32("2720");

        bytes32 originalHash = v.getHash(testUserOp, 300, 200);
        bytes32 modifiedHash = v.getHash(modifiedUserOp, 300, 200);

        assertEq(originalHash, modifiedHash);
    }

    function test_getHash_sameHashOn_paymasterAndData() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.paymasterAndData = hex"382A15C2bC4238a901daF270A09120A9F225473B"; //change entire data

        bytes32 originalHash = v.getHash(testUserOp, 300, 200);
        bytes32 modifiedHash = v.getHash(modifiedUserOp, 300, 200);

        assertEq(originalHash, modifiedHash);
    }

    function test_getHash_sameHashOn_signature() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.signature = hex"382A15C2bC4238"; //change entire data

        bytes32 originalHash = v.getHash(testUserOp, 300, 200);
        bytes32 modifiedHash = v.getHash(modifiedUserOp, 300, 200);

        assertEq(originalHash, modifiedHash);
    }

//----------------------------------------------------------------------------------------------------------------------------------

    function test_parsePaymasterAndData_returnData() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        bytes memory data = abi.encodePacked(address(v), uint(0), uint(300), uint(200), hex"8B89386EA80D89");
        (uint48 validUntil, uint48 validAfter, bytes memory signature) = v.parsePaymasterAndData(data);

        assertEq(validUntil, 300);
        assertEq(validAfter, 200);
        assertEq(signature, hex"8B89386EA80D89");
    }

    function test_parsePaymasterAndData_returnEmptySignature() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        bytes memory data = abi.encodePacked(address(v), uint(0), uint(300), uint(200));

        (uint48 validUntil, uint48 validAfter, bytes memory signature) = v.parsePaymasterAndData(data);

        assertEq(validUntil, 300);
        assertEq(validAfter, 200);
        assertEq(signature, hex"");
    }

    function test_parsePaymasterAndData_failOn_emptyData() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        vm.expectRevert();
        v.parsePaymasterAndData(hex"");
    }

    function test_parsePaymasterAndData_failOn_dataWithoutPaymasterAddress() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        bytes memory data = abi.encodePacked(uint(300), uint(200), hex"8B89386EA80D89");

        vm.expectRevert();
        v.parsePaymasterAndData(data);
    }

    function test_parsePaymasterAndData_failOn_dataWithoutValidTimes() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        bytes memory data = abi.encodePacked(address(v), uint(0), hex"8B89386EA80D89");

        vm.expectRevert();
        v.parsePaymasterAndData(data);
    }

//------------------------------------------------------------------------------------------------------------

    function test_validatePaymasterUserOp_failOn_senderIsNotEntrypoint() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        vm.expectRevert(bytes("Sender not EntryPoint"));
        v.validatePaymasterUserOp(testUserOp, "", 0);
    }

    function test_validatePaymasterUserOp_failOn_paymasterAndData_haveOnly_paymasterAddress() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.paymasterAndData = abi.encode(address(v)); //use paymaster address itself

        vm.expectRevert();
        vm.prank(address(entrypoint));
        v.validatePaymasterUserOp(modifiedUserOp, "", 0);
    }

    function test_validatePaymasterUserOp_failOn_paymasterAndData_withoutSignature() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.paymasterAndData = abi.encodePacked(address(v), uint(0), uint(300), uint(200), hex""); //signature empty: hex""

        vm.expectRevert(bytes("VerifyingPaymaster: invalid signature length in paymasterAndData"));
        vm.prank(address(entrypoint));
        v.validatePaymasterUserOp(modifiedUserOp, "", 0);
    }

    function test_validatePaymasterUserOp_failOn_paymasterAndData_withInvalidLengthSignature() public {
        address verifyingSigner = address(0x123);
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.paymasterAndData = abi.encodePacked(address(v), uint(0), uint(300), uint(200), hex"123456"); //signature with no 64 length

        vm.expectRevert(bytes("VerifyingPaymaster: invalid signature length in paymasterAndData"));
        vm.prank(address(entrypoint));
        v.validatePaymasterUserOp(modifiedUserOp, "", 0);
    }

    function test_validatePaymasterUserOp_successOn_signedUserOp() public {
        //this is the trusted address with their private key
        (address verifyingSigner, uint256 privateKey) = makeAddrAndKey("original_verifier");
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        //get userOp signed hash by the trusted private key
        bytes memory signedHash = signUserOp(v, modifiedUserOp, privateKey);
        //add hash to paymaster and data
        modifiedUserOp.paymasterAndData = abi.encodePacked(address(v), uint(0), uint(300), uint(200), signedHash);

        vm.prank(address(entrypoint));
        (, uint256 validationData) = v.validatePaymasterUserOp(modifiedUserOp, "", 0);
        
        //check if validationData ends with 0 (success)
        assertEq(validationData % 10, 0);
    }

    function test_validatePaymasterUserOp_rejectOn_userOp_signedByIntruder() public {
        //this is the trusted address
        (address verifyingSigner,) = makeAddrAndKey("original_verifier");
        VerifyingPaymaster v = new VerifyingPaymaster(entrypoint, verifyingSigner);

        //this is the intruder, they'll try to sign and send userOp to paymaster
        (, uint256 intruderKey) = makeAddrAndKey("intruder");


        PackedUserOperation memory modifiedUserOp = testUserOp;
        //get userOp signed hash by the intruder private key
        bytes memory signedHash = signUserOp(v, modifiedUserOp, intruderKey);
        //add hash to paymaster and data
        modifiedUserOp.paymasterAndData = abi.encodePacked(address(v), uint(0), uint(300), uint(200), signedHash);

        vm.prank(address(entrypoint));
        (, uint256 validationData) = v.validatePaymasterUserOp(modifiedUserOp, "", 0);
        
        //check if validationData ends with 1 (rejected)
        assertEq(validationData % 10, 1);
    }

    function signUserOp(VerifyingPaymaster vp, PackedUserOperation memory userOp, uint256 privateKey) internal view returns (bytes memory) {
        //Get hashed UserOp
        bytes32 hashedUserOp = vp.getHash(userOp, 300, 200);
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(hashedUserOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}