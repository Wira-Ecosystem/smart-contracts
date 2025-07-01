pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Guardian} from "../../src/Guardians.sol";
import {SimpleAccount} from "../../src/SimpleAccount.sol";
import {SimpleAccountFactory} from "../../src/SimpleAccountFactory.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

contract GuardianTest is Test {
    IEntryPoint entrypoint =
        IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    SimpleAccountFactory factory;
    SimpleAccount account;
    Guardian guardian;
    address owner;

    address guardian1Addr;
    address guardian2Addr;
    address guardian3Addr;
    bytes32 guardian1Hash;
    bytes32 guardian2Hash;
    bytes32 guardian3Hash;

    function setUp() public {
        factory = new SimpleAccountFactory();
        //initialize with entrypoint and fake tokenPaymaster
        factory.initialize(entrypoint, address(0x123));
        owner = vm.addr(0x123);

        account = factory.createAccount(owner, 123456);
        guardian = Guardian(account.getGuardian());
        guardian1Addr = vm.addr(uint256(1));
        guardian2Addr = vm.addr(uint256(2));
        guardian3Addr = vm.addr(uint256(3));

        guardian1Hash = keccak256(abi.encodePacked(guardian1Addr));
        guardian2Hash = keccak256(abi.encodePacked(guardian2Addr));
        guardian3Hash = keccak256(abi.encodePacked(guardian3Addr));
    }

    function test_InviteGuardian() public {
        vm.prank(address(account));
        guardian.invite(guardian1Hash);

        (Guardian.Status state, uint40 invitedAt) = guardian.guardians(
            guardian1Hash
        );
        assertEq(uint(state), uint(Guardian.Status.PENDING));
        assertEq(invitedAt, block.timestamp);
    }

    function test_InviteGuardianOnlyOwner() public {
        vm.prank(vm.addr(0x456));
        vm.expectRevert(bytes("only owner"));
        guardian.invite(guardian1Hash);
    }

    function test_InviteGuardianZeroHash() public {
        vm.prank(address(account));
        vm.expectRevert(bytes("zero"));
        guardian.invite(bytes32(0));
    }

    function test_InviteGuardianAlreadyExists() public {
        vm.prank(address(account));
        guardian.invite(guardian1Hash);
        vm.prank(address(account));
        vm.expectRevert(bytes("exists"));
        guardian.invite(guardian1Hash);
    }

    function test_AcceptGuardianInvitation() public {
        vm.prank(address(account));
        guardian.invite(guardian1Hash);

        vm.prank(guardian1Addr);
        guardian.accept(guardian1Hash);

        (Guardian.Status state, ) = guardian.guardians(guardian1Hash);
        assertEq(uint(state), uint(Guardian.Status.ACCEPTED));
        assertTrue(guardian.isGuardian(guardian1Hash));
    }

    function test_AcceptGuardianNotPending() public {
        vm.expectRevert(bytes("not pending"));
        guardian.accept(guardian1Hash);
    }

    function test_RemoveGuardian() public {
        setupGuardian(guardian1Addr, guardian1Hash);

        vm.prank(address(account));
        guardian.remove(guardian1Hash);

        assertFalse(guardian.isGuardian(guardian1Hash));
    }

    function test_RemoveGuardianOnlyOwner() public {
        vm.prank(vm.addr(0x456));
        vm.expectRevert(bytes("only owner"));
        guardian.remove(guardian1Hash);
    }

    function test_SetQuorum() public {
        vm.prank(address(account));
        guardian.setQuorum(3);
        assertEq(guardian.requiredApprovals(), 3);
    }

    function test_SetQuorumZero() public {
        vm.prank(address(account));
        vm.expectRevert(bytes("zero"));
        guardian.setQuorum(0);
    }

    function test_SetQuorumOnlyOwner() public {
        vm.prank(vm.addr(0x456));
        vm.expectRevert(bytes("only owner"));
        guardian.setQuorum(2);
    }

    function test_ApproveRecoveryWithOneGuardian() public {
        setupGuardian(guardian1Addr, guardian1Hash);

        address newOwner = vm.addr(0x999);

        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        assertEq(account.owner(), newOwner);

        bytes32 recKey = keccak256(abi.encode(newOwner));
        (address recoveryOwner, uint8 approvals, bool executed, ) = guardian
            .recoveries(recKey);
        assertEq(recoveryOwner, newOwner);
        assertEq(approvals, 1);
        assertTrue(executed);
    }

    function test_ApproveRecoveryGuardianNotAccepted() public {
        address newOwner = vm.addr(0x999);
        vm.expectRevert(abi.encodeWithSelector(Guardian.InvalidGuardian.selector));
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
    }

    function test_ApproveRecoveryAlreadyVoted() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        address newOwner = vm.addr(0x999);

        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        vm.expectRevert(abi.encodeWithSelector(Guardian.AlreadyVoted.selector));
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
    }

    function test_ApproveRecoveryMultipleGuardians() public {
        vm.prank(address(account));
        guardian.setQuorum(2);

        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        address newOwner = vm.addr(0x999);

        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        assertEq(account.owner(), owner);

        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);
        assertEq(account.owner(), newOwner);

        bytes32 recKey = keccak256(abi.encode(newOwner));
        (address recoveryOwner, uint8 approvals, bool executed, ) = guardian
            .recoveries(recKey);
        assertEq(recoveryOwner, newOwner);
        assertEq(approvals, 2);
        assertTrue(executed);
    }

    function test_MultipleRecoveryProposals() public {
        vm.prank(address(account));
        guardian.setQuorum(2);

        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        address newOwner1 = vm.addr(0x999);
        address newOwner2 = vm.addr(0x888);

        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner1);

        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner2);

        vm.prank(guardian3Addr);
        guardian.approveRecovery(newOwner1);

        assertEq(account.owner(), newOwner1);
    }

    function test_RecoveryAlreadyExecuted() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);

        address newOwner = vm.addr(0x999);

        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);

        bytes32 recKey = keccak256(abi.encode(newOwner));
        (, uint8 approvals, bool executed, ) = guardian.recoveries(recKey);
        assertEq(approvals, 2);
        assertTrue(executed);
    }

    function test_GuardianInvitedEvent() public {
        vm.prank(address(account));

        vm.expectEmit(true, false, false, false);
        emit Guardian.GuardianInvited(guardian1Hash);

        guardian.invite(guardian1Hash);
    }

    function test_GuardianAcceptedEvent() public {
        vm.prank(address(account));
        guardian.invite(guardian1Hash);

        vm.prank(guardian1Addr);
        vm.expectEmit(true, false, false, true);
        emit Guardian.GuardianAccepted(guardian1Hash, guardian1Addr);

        guardian.accept(guardian1Hash);
    }

    function test_RecoveryEvents() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        address newOwner = vm.addr(0x999);
        vm.expectEmit(true, false, false, true);
        emit Guardian.RecoveryProposed(
            newOwner,
            block.timestamp + guardian.RECOVERY_PERIOD()
        );
        vm.expectEmit(true, true, false, false);

        emit Guardian.RecoveryApproved(newOwner, guardian1Hash);

        vm.expectEmit(true, false, false, false);

        emit Guardian.RecoveryExecuted(newOwner);

            vm.prank(guardian1Addr);

        guardian.approveRecovery(newOwner);
    }

    function test_IsGuardianFunction() public {
        assertFalse(guardian.isGuardian(guardian1Hash));
        setupGuardian(guardian1Addr, guardian1Hash);
        assertTrue(guardian.isGuardian(guardian1Hash));
        vm.prank(address(account));
        guardian.remove(guardian1Hash);
        assertFalse(guardian.isGuardian(guardian1Hash));
    }

    function test_VotedMapping() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        address newOwner = vm.addr(0x999);
        bytes32 recKey = keccak256(abi.encode(newOwner));
        assertFalse(guardian.voted(guardian1Hash, recKey));

        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        assertTrue(guardian.voted(guardian1Hash, recKey));
    }
    //helper
    function setupGuardian(
        address guardianAddr,
        bytes32 guardianHash
    ) internal {
        vm.prank(address(account));
        guardian.invite(guardianHash);

        vm.prank(guardianAddr);
        guardian.accept(guardianHash);
    }
}
