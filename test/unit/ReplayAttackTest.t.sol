// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAccount} from "../../src/SimpleAccount.sol";
import {SimpleAccountFactory} from "../../src/SimpleAccountFactory.sol";
import {
    IEntryPoint,
    PackedUserOperation
} from "@account-abstraction/interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol"; // ← nuevo

contract ReplayAttackTest1 is Test {
    IEntryPoint constant ENTRYPOINT =
        // IEntryPoint(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789); // OP Sepolia
        IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032); // Sepolia

    SimpleAccountFactory factory;
    SimpleAccount        account;

    uint256 constant OWNER_PK = 0x123;
    address owner    = vm.addr(OWNER_PK);
    address receiver = address(0x999);

    function setUp() public {
        factory = new SimpleAccountFactory(ENTRYPOINT, msg.sender);

        account = factory.createAccount(owner, 123456);
        vm.deal(address(account), 10 ether); 
    }

    function _pack(uint128 hi, uint128 lo) internal pure returns (bytes32) {
        return bytes32((uint256(hi) << 128) | uint256(lo));
    }

    function _buildOp(uint256 nonce) internal view returns (PackedUserOperation memory op) {
        op.sender  = address(account);
        op.nonce   = nonce;
        op.callData = abi.encodeWithSelector(SimpleAccount.execute.selector,
                                             receiver, 1 ether, "");
        op.accountGasLimits    = _pack(100_000, 150_000);
        op.preVerificationGas  = 60_000;
        uint128 fee = uint128(tx.gasprice);
        op.gasFees             = _pack(fee, fee);

        bytes32 opHash  = ENTRYPOINT.getUserOpHash(op);
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(opHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, ethHash);
        op.signature = abi.encodePacked(r, s, v);
    }

    function test_ReplayAttack() public {
        PackedUserOperation [] memory batch = new PackedUserOperation[](1);
        batch[0] = _buildOp(0);

        ENTRYPOINT.handleOps(batch, payable(address(this)));   // 1er intento todo bine
        assertEq(receiver.balance, 1 ether);

        vm.expectRevert();
        ENTRYPOINT.handleOps(batch, payable(address(this))); // 2do intento TIENE que fallar
    }

    receive() external payable {}
}
