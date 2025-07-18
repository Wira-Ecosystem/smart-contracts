// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAccountFactory} from "../../src/SimpleAccountFactory.sol";
import {SimpleAccount} from "../../src/SimpleAccount.sol";
import {Guardian} from "../../src/Guardians.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";
import {Vm} from "forge-std/Vm.sol";
contract ChangeQuorumWorkflowTest is Test {
    IEntryPoint entrypoint = IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    SimpleAccountFactory factory;
    SimpleAccount account;
    Guardian guardian;
    address owner;

    // Direcciones de guardians
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
        factory.initialize(address(0x789));
        
        owner = address(0x123);
        account = factory.createAccount(owner, 123456);

        // Crear guardian para la cuenta
        factory.createGuardianForAccount(address(account), 1);
        guardian = Guardian(account.getGuardian());

        // Configurar direcciones de guardians
        guardian1Addr = vm.addr(uint256(1));
        guardian2Addr = vm.addr(uint256(2));
        guardian3Addr = vm.addr(uint256(3));

        guardian1Hash = keccak256(abi.encodePacked(guardian1Addr));
        guardian2Hash = keccak256(abi.encodePacked(guardian2Addr));
        guardian3Hash = keccak256(abi.encodePacked(guardian3Addr));
    }

    function test_ChangeQuorumFromOneToThree() public {
        // Verificar que el quorum inicial es 1
        assertEq(guardian.requiredApprovals(), 1);

        //sdgsdgsgd
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        // Cambiar el quorum a 3 (solo el owner de la cuenta puede hacerlo)
        vm.prank(address(account));
        guardian.setQuorum(3);

        // Verificar que el quorum se haya cambiado
        assertEq(guardian.requiredApprovals(), 3);
    }

    function test_RecoveryWithNewQuorum() public {
        // Configurar 3 guardians
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        // Cambiar el quorum a 2
        vm.prank(address(account));
        guardian.setQuorum(2);

        address newOwner = vm.addr(0x999);
        address originalOwner = account.owner();

        // Primer guardian aprueba la recuperación
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que la recuperación aún no se ha ejecutado
        assertEq(account.owner(), originalOwner);

        // Segundo guardian aprueba la recuperación - ahora debería ejecutarse
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que la recuperación se ejecutó
        assertEq(account.owner(), newOwner);

        // Verificar el estado de la recuperación
        (uint8 approvals, bool executed, , bool expired) = guardian.getRecoveryStatus(newOwner);
        assertEq(approvals, 2);
        assertTrue(executed);
        assertFalse(expired);
    }

    function test_RecoveryFailsWithInsufficientApprovals() public {
        // Configurar 3 guardians
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        // Cambiar el quorum a 3
        vm.prank(address(account));
        guardian.setQuorum(3);

        address newOwner = vm.addr(0x999);
        address originalOwner = account.owner();

        // Solo 2 guardians aprueban la recuperación
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que la recuperación NO se ha ejecutado
        assertEq(account.owner(), originalOwner);

        // Verificar el estado de la recuperación
        (uint8 approvals, bool executed, , bool expired) = guardian.getRecoveryStatus(newOwner);
        assertEq(approvals, 2);
        assertFalse(executed);
        assertFalse(expired);
    }

    function test_RecoverySucceedsAfterThirdApproval() public {
        // Configurar 3 guardians
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        // Cambiar el quorum a 3
        vm.prank(address(account));
        guardian.setQuorum(3);

        address newOwner = vm.addr(0x999);
        address originalOwner = account.owner();

        // Los primeros 2 guardians aprueban
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que aún no se ha ejecutado
        assertEq(account.owner(), originalOwner);

        // El tercer guardian aprueba - ahora debería ejecutarse
        vm.prank(guardian3Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que la recuperación se ejecutó
        assertEq(account.owner(), newOwner);

        // Verificar el estado final
        (uint8 approvals, bool executed, , bool expired) = guardian.getRecoveryStatus(newOwner);
        assertEq(approvals, 3);
        assertTrue(executed);
        assertFalse(expired);
    }

    function test_OnlyOwnerCanChangeQuorum() public {
        // Intentar cambiar el quorum desde una dirección no autorizada
        vm.prank(guardian1Addr);
        vm.expectRevert(bytes("only owner"));
        guardian.setQuorum(2);

        // Verificar que el quorum no cambió
        assertEq(guardian.requiredApprovals(), 1);
    }

    function test_CannotSetQuorumToZero() public {
        vm.prank(address(account));
        vm.expectRevert(bytes("zero"));
        guardian.setQuorum(0);

        // Verificar que el quorum no cambió
        assertEq(guardian.requiredApprovals(), 1);
    }

    function test_QuorumChangedEvent() public {
        vm.prank(address(account));
        
        // Verificar que se emite el evento correcto
        vm.expectEmit(true, false, false, true);
        emit Guardian.QuorumChanged(3);
        
        guardian.setQuorum(3);
    }

    // Función helper para configurar un guardian
    function setupGuardian(address guardianAddr, bytes32 guardianHash) internal {
        // Invitar al guardian
        vm.prank(address(account));
        guardian.invite(guardianHash);

        // Aceptar la invitación
        vm.prank(guardianAddr);
        guardian.accept(guardianHash);

        // Verificar que el guardian está activo
        assertTrue(guardian.isGuardian(guardianHash));
    }
}

