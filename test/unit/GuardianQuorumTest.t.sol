// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Guardian} from "../../src/Guardians.sol";
import {SimpleAccount} from "../../src/SimpleAccount.sol";
import {SimpleAccountFactory} from "../../src/SimpleAccountFactory.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

contract GuardianQuorumTest is Test {
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
        address fcOwner = address(0x173);
        factory = new SimpleAccountFactory(entrypoint, fcOwner);

        vm.prank(fcOwner);
        factory.initialize(address(0x123));

        owner = vm.addr(0x123);
        account = factory.createAccount(owner, 123456);

        factory.createGuardianForAccount(address(account), 1);
        guardian = Guardian(account.getGuardian());

        guardian1Addr = vm.addr(uint256(1));
        guardian2Addr = vm.addr(uint256(2));
        guardian3Addr = vm.addr(uint256(3));

        guardian1Hash = keccak256(abi.encodePacked(guardian1Addr));
        guardian2Hash = keccak256(abi.encodePacked(guardian2Addr));
        guardian3Hash = keccak256(abi.encodePacked(guardian3Addr));
    }

    function setupGuardian(address gAddr, bytes32 gHash) internal {
        vm.prank(address(account));
        guardian.invite(gHash);

        vm.prank(gAddr);
        guardian.accept(gHash);
    }

    /// Elimina un guardián y verifica que se reduzca automáticamente al nuevo totalGuards.
    function test_RemoveGuardian_AutoShrinksQuorum() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        vm.prank(address(account));
        guardian.setQuorum(3);

        assertEq(guardian.totalGuards(), 3);
        assertEq(guardian.requiredApprovals(), 3);

        vm.prank(address(account));
        guardian.remove(guardian3Hash);

        assertEq(guardian.totalGuards(), 2);
        assertEq(guardian.requiredApprovals(), 2);
    }

    // Comprueba que la recuperación se ejecute correctamente después de eliminar un guardián.
    function test_RecoveryExecutesAfterAutoShrink() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        vm.prank(address(account));
        guardian.setQuorum(3);

        address newOwner = vm.addr(0x999);
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        vm.prank(address(account));
        guardian.remove(guardian3Hash);

        assertEq(guardian.requiredApprovals(), 2);

        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);

        (uint8 approvals, bool executed,,) = guardian.getRecoveryStatus(newOwner);
        assertTrue(executed, "Recovery no se ejecuto");
        assertEq(approvals, 2, "Numero de aprobaciones incorrecto");
        assertEq(account.owner(), newOwner, "Owner no cambio");
    }

    /// Elimina guardianes hasta quedar 1 y comprueba que el quórum nunca supere el total de guardianes.
    function test_MultipleRemovals_QuorumAlwaysValid() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        vm.prank(address(account));
        guardian.setQuorum(3);

        vm.startPrank(address(account));
        guardian.remove(guardian3Hash);
        guardian.remove(guardian2Hash);
        vm.stopPrank();

        assertEq(guardian.totalGuards(), 1);
        assertEq(guardian.requiredApprovals(), 1);
    }
}
