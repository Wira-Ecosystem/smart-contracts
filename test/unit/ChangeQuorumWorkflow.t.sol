// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DebtAccountFactory} from "../../src/DebtAccountFactory.sol";
import {SimpleAccountV2} from "../../src/SimpleAccountV2.sol";
import {Guardian} from "../../src/Guardians.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";
import {Vm} from "forge-std/Vm.sol";
contract ChangeQuorumWorkflowTest is Test {
    IEntryPoint entrypoint = IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    DebtAccountFactory factory;
    SimpleAccountV2 account;
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
        factory = new DebtAccountFactory(entrypoint, msg.sender);
        
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
        // Primero configurar suficientes guardianes
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);
        
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


    // ========== CASOS CRÍTICOS ADICIONALES ==========
    
    function test_QuorumChangeHigherThanAvailableGuardians() public {
        // Configurar solo 2 guardians
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);

        // Intentar establecer quorum más alto que guardians disponibles debería fallar
        vm.prank(address(account));
        vm.expectRevert(); // Esperamos que falle con QuorumExceeded
        guardian.setQuorum(5); // 5 > 2 guardians disponibles

        // El quorum debería seguir siendo 1 (valor inicial)
        assertEq(guardian.requiredApprovals(), 1);
    }

    function test_QuorumChangeToMaxUint8() public {
        // Configurar suficientes guardianes para test realista
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);
        
        // Probar con el valor máximo permitido (número de guardianes)
        vm.prank(address(account));
        guardian.setQuorum(3);
        
        assertEq(guardian.requiredApprovals(), 3);
        
        // Verificar que el evento se emite correctamente para un cambio válido
        vm.prank(address(account));
        vm.expectEmit(true, false, false, true);
        emit Guardian.QuorumChanged(2);
        guardian.setQuorum(2);
        
        assertEq(guardian.requiredApprovals(), 2);
    }

    function test_QuorumChangeAffectsOngoingRecovery() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);
        
        // Iniciar recuperación con quorum 1
        address newOwner = vm.addr(0x999);
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        // Verificar que se ejecutó con quorum 1
        assertEq(account.owner(), newOwner);
        
        // Cambiar el quorum para futuras recuperaciones
        vm.prank(address(account));
        guardian.setQuorum(3);
        
        // Intentar nueva recuperación con nuevo quorum
        address newOwner2 = vm.addr(0x888);
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner2);
        
        // No debería ejecutarse con solo 1 voto
        assertEq(account.owner(), newOwner); // Sigue siendo el anterior
    }

    function test_QuorumChangeAfterSomeVotesButBeforeExecution() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);
        
        // Establecer quorum alto inicialmente
        vm.prank(address(account));
        guardian.setQuorum(3);
        
        address newOwner = vm.addr(0x999);
        address originalOwner = account.owner();
        
        // Dos guardians votan pero no es suficiente
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);
        
        // Verificar que aún no se ejecutó
        assertEq(account.owner(), originalOwner);
        
        // Cambiar quorum a 2 (debería ejecutarse ahora? NO - solo afecta nuevas recuperaciones)
        vm.prank(address(account));
        guardian.setQuorum(2);
        
        // La recuperación existente sigue necesitando 3 votos (valor al momento de inicio)
        assertEq(account.owner(), originalOwner);
        
        // El tercer voto debería ejecutarla
        vm.prank(guardian3Addr);
        guardian.approveRecovery(newOwner);
        
        assertEq(account.owner(), newOwner);
    }

    function test_RemoveGuardianAfterQuorumChange() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);
        
        // Establecer quorum alto
        vm.prank(address(account));
        guardian.setQuorum(3);
        
        // Remover un guardian - esto debería ajustar automáticamente el quorum
        vm.prank(address(account));
        guardian.remove(guardian3Hash);
        
        // El contrato ajusta automáticamente el quorum cuando se remueve un guardian
        // y el quorum actual es mayor que el número de guardianes restantes
        assertEq(guardian.requiredApprovals(), 2); // Se ajustó de 3 a 2
        assertFalse(guardian.isGuardian(guardian3Hash));
        
        // Ahora la recuperación debería ser posible con 2 votos
        address newOwner = vm.addr(0x999);
        
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);
        
        // Debería ejecutarse ahora
        assertEq(account.owner(), newOwner);
        
        (uint8 approvals, bool executed,,) = guardian.getRecoveryStatus(newOwner);
        assertEq(approvals, 2);
        assertTrue(executed);
    }

    function test_QuorumChangeWithRemovedGuardianVotes() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);
        
        vm.prank(address(account));
        guardian.setQuorum(3);
        
        address newOwner = vm.addr(0x999);
        
        // Guardian1 vota
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        // Remover guardian1 después de que votó
        vm.prank(address(account));
        guardian.remove(guardian1Hash);
        
        // Guardian2 y Guardian3 votan
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);
        
        vm.prank(guardian3Addr);
        guardian.approveRecovery(newOwner);
        
        // La recuperación debería ejecutarse (3 votos totales)
        assertEq(account.owner(), newOwner);
    }

    function test_MultipleQuorumChangesInSingleRecovery() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        
        // Iniciar con quorum 1
        address newOwner = vm.addr(0x999);
        
        // Cambiar a quorum 2 antes de votar
        vm.prank(address(account));
        guardian.setQuorum(2);
        
        // Primer voto
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        assertNotEq(account.owner(), newOwner);
        
        // Cambiar quorum otra vez (no debería afectar recuperación en curso)
        vm.prank(address(account));
        guardian.setQuorum(1);
        
        // La recuperación sigue necesitando 2 votos
        assertNotEq(account.owner(), newOwner);
        
        // Segundo voto debería ejecutar
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);
        
        assertEq(account.owner(), newOwner);
    }

    function test_QuorumChangeAfterRecoveryExpired() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        
        vm.prank(address(account));
        guardian.setQuorum(2);
        
        address newOwner = vm.addr(0x999);
        
        // Solo un voto
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        // Avanzar tiempo para que expire
        vm.warp(block.timestamp + 4 days);
        
        // Cambiar quorum después de expiración
        vm.prank(address(account));
        guardian.setQuorum(1);
        
        // Intentar votar debería limpiar la recuperación expirada
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner); // Esto debería crear nueva propuesta
        
        // Debería ejecutarse inmediatamente con quorum 1
        assertEq(account.owner(), newOwner);
    }

    function test_QuorumBoundaryConditions() public {
        // Configurar algunos guardianes primero
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);
        
        // Test quorum = 1
        vm.prank(address(account));
        guardian.setQuorum(1);
        assertEq(guardian.requiredApprovals(), 1);
        
        // Test incremento gradual hasta el máximo permitido (número de guardianes)
        for(uint8 i = 2; i <= 3; i++) {
            vm.prank(address(account));
            guardian.setQuorum(i);
            assertEq(guardian.requiredApprovals(), i);
        }
        
        // Test que no se puede exceder el número de guardianes
        vm.prank(address(account));
        vm.expectRevert(); // Debería fallar
        guardian.setQuorum(4); // 4 > 3 guardianes
        
        // Verificar que el quorum sigue siendo 3
        assertEq(guardian.requiredApprovals(), 3);
    }

    function test_QuorumChangeEventSequence() public {
        // Configurar suficientes guardianes para los tests
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);
        
        // Verificar múltiples cambios de quorum y sus eventos
        vm.startPrank(address(account));
        
        // Primer cambio válido
        vm.expectEmit(true, false, false, true);
        emit Guardian.QuorumChanged(3);
        guardian.setQuorum(3);
        
        // Segundo cambio válido
        vm.expectEmit(true, false, false, true);
        emit Guardian.QuorumChanged(1);
        guardian.setQuorum(1);
        
        // Tercer cambio válido
        vm.expectEmit(true, false, false, true);
        emit Guardian.QuorumChanged(2);
        guardian.setQuorum(2);
        
        vm.stopPrank();
        
        assertEq(guardian.requiredApprovals(), 2);
    }
}

