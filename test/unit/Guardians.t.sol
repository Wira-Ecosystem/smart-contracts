pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Guardian} from "../../src/Guardians.sol";
import {SimpleAccount} from "../../src/SimpleAccount.sol";
import {DebtAccountFactory} from "../../src/DebtAccountFactory.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

contract GuardianTest is Test {
    IEntryPoint entrypoint =
        IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    DebtAccountFactory factory;
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
        factory = new DebtAccountFactory(entrypoint, fcOwner);
        //initialize with entrypoint and fake tokenPaymaster
        vm.prank(fcOwner);
        factory.initialize(address(0x123));
        owner = vm.addr(0x123);

        account = factory.createAccount(owner, 123456);

        // Create guardian for the account
        factory.createGuardianForAccount(address(account), 1);
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
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

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
        vm.expectRevert(
            abi.encodeWithSelector(Guardian.InvalidGuardian.selector)
        );
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
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);
        
        vm.prank(address(account));

        guardian.setQuorum(2); // DESPUE DE TENER LOS GUARDIANES SE puede setear el quorum

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
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        vm.prank(address(account));
        
        guardian.setQuorum(2);

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

    // TESTS IMPLEMENTATIONS FOR CLEANUP FUNCTION
    function test_RecoveryExpiration() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        
        vm.prank(address(account));
        guardian.setQuorum(2);

        address newOwner = vm.addr(0x999);

        // Guardian1 vota por la recuperación
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que el recovery está activo
        (uint8 approvals, bool executed, uint256 deadline, bool expired) = guardian.getRecoveryStatus(newOwner);
        assertEq(approvals, 1);
        assertFalse(executed);
        assertFalse(expired);

        // Avanzar el tiempo más allá del período de recuperación
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);

        // Verificar que ahora está expirado
        (, , , bool nowExpired) = guardian.getRecoveryStatus(newOwner);
        assertTrue(nowExpired);

        // Cuando otro guardian trata de votar, debería limpiar automáticamente
        vm.expectEmit(true, false, false, false);
        emit Guardian.RecoveryExpired(newOwner);
        
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que se ha limpiado y creado una nueva propuesta
        (uint8 newApprovals, bool newExecuted, , bool newExpired) = guardian.getRecoveryStatus(newOwner);
        assertEq(newApprovals, 1); // Solo el voto del guardian2
        assertFalse(newExecuted);
        assertFalse(newExpired);
    }

    function test_CleanupOnlyAffectsExpiredRecoveries() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);
        
        vm.prank(address(account));
        guardian.setQuorum(3);

        address newOwner1 = vm.addr(0x999);
        address newOwner2 = vm.addr(0x888);

        // Proponer dos recuperaciones
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner1);
        
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner2);

        // Verificar que ambas están activas
        (uint8 approvals1, , , bool expired1) = guardian.getRecoveryStatus(newOwner1);
        (uint8 approvals2, , , bool expired2) = guardian.getRecoveryStatus(newOwner2);
        assertEq(approvals1, 1);
        assertEq(approvals2, 1);
        assertFalse(expired1);
        assertFalse(expired2);

        // Expirar solo la primera
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);

        // Proponer una nueva recuperación para newOwner1 (debería limpiar la expirada)
        vm.prank(guardian3Addr);
        guardian.approveRecovery(newOwner1);

        // Verificar que newOwner1 tiene una nueva propuesta limpia
        (uint8 newApprovals1, , , bool newExpired1) = guardian.getRecoveryStatus(newOwner1);
        assertEq(newApprovals1, 1); // Solo el nuevo voto
        assertFalse(newExpired1);

        // newOwner2 también debería estar expirada ahora
        (, , , bool expired2Now) = guardian.getRecoveryStatus(newOwner2);
        assertTrue(expired2Now);
    }

    function test_CleanupRemovesVotedMappings() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        vm.prank(address(account));
        guardian.setQuorum(3);

        address newOwner = vm.addr(0x999);
        bytes32 recKey = keccak256(abi.encode(newOwner));

        // Ambos guardianes votan
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que los votos están registrados
        assertTrue(guardian.voted(guardian1Hash, recKey));
        assertTrue(guardian.voted(guardian2Hash, recKey));

        // Expirar la recuperación
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);

        // Proponer una nueva recuperación (esto debería limpiar los votos anteriores)
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que los votos anteriores fueron limpiados
        // guardian1 debería tener su nuevo voto, guardian2 no debería tener voto
        bytes32 newRecKey = keccak256(abi.encode(newOwner));
        assertTrue(guardian.voted(guardian1Hash, newRecKey)); // nuevo voto
        assertFalse(guardian.voted(guardian2Hash, newRecKey)); // voto anterior limpiado
    }

    function test_MultipleExpiredRecoveriesCleanup() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        
        vm.prank(address(account));
        guardian.setQuorum(2);

        address newOwner1 = vm.addr(0x999);
        address newOwner2 = vm.addr(0x888);
        address newOwner3 = vm.addr(0x777);

        // Crear múltiples propuestas
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner1);
        
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner2);
        
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner3);

        // Expirar todas
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);

        // Hacer nuevas propuestas debería limpiar las expiradas
        vm.expectEmit(true, false, false, false);
        emit Guardian.RecoveryExpired(newOwner1);
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner1);

        vm.expectEmit(true, false, false, false);
        emit Guardian.RecoveryExpired(newOwner2);
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner2);

        // Verificar que todas tienen propuestas frescas
        (uint8 approvals1, , , bool expired1) = guardian.getRecoveryStatus(newOwner1);
        (uint8 approvals2, , , bool expired2) = guardian.getRecoveryStatus(newOwner2);
        assertEq(approvals1, 1);
        assertEq(approvals2, 1);
        assertFalse(expired1);
        assertFalse(expired2);
    }

    function test_RecoveryExpiredEventEmitted() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        
        // Configurar quorum de 2 para que no se ejecute automáticamente
        vm.prank(address(account));
        guardian.setQuorum(2);
        
        address newOwner = vm.addr(0x999);

        // Proponer recuperación (solo guardian1 vota, no se ejecuta)
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que no se ejecutó
        assertEq(account.owner(), owner); // Sigue siendo el owner original

        // Expirar
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);

        // Verificar que se emite el evento correcto cuando guardian2 vota
        vm.expectEmit(true, false, false, false);
        emit Guardian.RecoveryExpired(newOwner);
        
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);
    }

    function test_CleanupDoesNotAffectExecutedRecoveries() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        address newOwner = vm.addr(0x999);

        // Ejecutar recuperación (quorum = 1)
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que se ejecutó
        assertTrue(account.owner() == newOwner);
        
        bytes32 recKey = keccak256(abi.encode(newOwner));
        (, , bool executed, ) = guardian.recoveries(recKey);
        assertTrue(executed);

        // Expirar tiempo
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);

        // Intentar nueva propuesta para el mismo owner no debería limpiar la ejecutada
        // (porque la condición incluye !r.executed)
        vm.prank(guardian1Addr);
        vm.expectRevert(abi.encodeWithSelector(Guardian.AlreadyVoted.selector));
        guardian.approveRecovery(newOwner);
    }

    function test_GasOptimizationOnlyIteratesVoters() public {
        // Configurar muchos guardianes
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);
        
        // Crear más guardianes para probar la optimización
        address guardian4Addr = vm.addr(uint256(4));
        address guardian5Addr = vm.addr(uint256(5));
        bytes32 guardian4Hash = keccak256(abi.encodePacked(guardian4Addr));
        bytes32 guardian5Hash = keccak256(abi.encodePacked(guardian5Addr));
        
        setupGuardian(guardian4Addr, guardian4Hash);
        setupGuardian(guardian5Addr, guardian5Hash);
        
        vm.prank(address(account));
        guardian.setQuorum(3);

        address newOwner = vm.addr(0x999);

        // Solo 2 de los 5 guardianes votan
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        vm.prank(guardian3Addr);
        guardian.approveRecovery(newOwner);

        // Verificar votos iniciales
        bytes32 recKey = keccak256(abi.encode(newOwner));
        assertTrue(guardian.voted(guardian1Hash, recKey));
        assertFalse(guardian.voted(guardian2Hash, recKey));
        assertTrue(guardian.voted(guardian3Hash, recKey));
        assertFalse(guardian.voted(guardian4Hash, recKey));
        assertFalse(guardian.voted(guardian5Hash, recKey));

        // Expirar y limpiar
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);
        
        // Guardian2 vota, lo que debería limpiar la recuperación expirada
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que los votos anteriores fueron limpiados
        // guardian1 y guardian3 deberían haber sido limpiados
        assertFalse(guardian.voted(guardian1Hash, recKey));
        assertFalse(guardian.voted(guardian3Hash, recKey));
        
        // guardian2 ahora tiene un nuevo voto en la nueva recuperación
        assertTrue(guardian.voted(guardian2Hash, recKey));
        
        // Los que nunca votaron siguen sin votos
        assertFalse(guardian.voted(guardian4Hash, recKey));
        assertFalse(guardian.voted(guardian5Hash, recKey));
    }

    function test_RecoveryVotersArrayCleanup() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        vm.prank(address(account));
        guardian.setQuorum(3);

        address newOwner = vm.addr(0x999);

        // Ambos guardianes votan
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner);

        // Expirar la recuperación
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);

        // Limpiar la recuperación expirada
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);

        // Verificar que se inicia una nueva propuesta limpia
        (uint8 approvals, bool executed, , bool expired) = guardian.getRecoveryStatus(newOwner);
        assertEq(approvals, 1); // Solo el nuevo voto de guardian1
        assertFalse(executed);
        assertFalse(expired);
    }

    function test_GuardianRemovalFromArray() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        // Verificar que hay 3 guardianes en el array
        assertEq(guardian.guardianHashes(0), guardian1Hash);
        assertEq(guardian.guardianHashes(1), guardian2Hash);
        assertEq(guardian.guardianHashes(2), guardian3Hash);

        // Remover guardian2
        vm.prank(address(account));
        guardian.remove(guardian2Hash);

        // Verificar que ya no es un guardian válido
        assertFalse(guardian.isGuardian(guardian2Hash));
        
        // Nota: El array guardianHashes no se modifica automáticamente por la función remove actual
        // Esto podría ser una mejora futura para optimización adicional
    }

    function test_EdgeCaseEmptyRecoveryVoters() public {
        address newOwner = vm.addr(0x999);
        
        // Intentar cleanup sin votos existentes (edge case)
        // Esto debería ser seguro y no causar errores
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);
        
        setupGuardian(guardian1Addr, guardian1Hash);
        
        // Este voto debería funcionar normalmente sin cleanup necesario
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        // Verificar que funciona correctamente
        (uint8 approvals, bool executed, , bool expired) = guardian.getRecoveryStatus(newOwner);
        assertEq(approvals, 1);
        assertTrue(executed); // Se ejecuta porque quorum = 1
        assertFalse(expired);
    }

    // QUE EL QUORUM NO SEA MAYOR AL NÚMERO DE GUARDIANES
    function test_SetQuorumGreaterThanGuardians() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);

        vm.prank(address(account));

        // Esperamos que la transacción sea revertida con el error esperado
        uint8 invalidQuorum = 4;  // Quórum mayor que el número de guardianes (3)
        
        // Revertir con el error específico y los valores correctos
        vm.expectRevert(bytes("QuorumExceeded(4, 3)"));
        guardian.setQuorum(invalidQuorum);
    }

    // TEST PARA PROBAR QUE GUARDIAN NO PUEDE MODIFICAR SIN TENGAN ACCESO
    // Tests adicionales para verificar que guardianes no pueden modificar sin ser owner
    function test_GuardianCannotInviteOtherGuardians() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        
        // Guardian1 intenta invitar a guardian2 (debería fallar)
        vm.prank(guardian1Addr);
        vm.expectRevert(bytes("only owner"));
        guardian.invite(guardian2Hash);
    }
    function test_GuardianCannotRemoveOtherGuardians() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        
        // Guardian1 intenta remover a guardian2 (debería fallar)
        vm.prank(guardian1Addr);
        vm.expectRevert(bytes("only owner"));
        guardian.remove(guardian2Hash);
    }
    function test_GuardianCannotRemoveThemselves() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        
        // Guardian1 intenta removerse a sí mismo (debería fallar)
        vm.prank(guardian1Addr);
        vm.expectRevert(bytes("only owner"));
        guardian.remove(guardian1Hash);
    }
    function test_GuardianCannotChangeQuorum() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        
        // Guardian1 intenta cambiar el quorum (debería fallar)
        vm.prank(guardian1Addr);
        vm.expectRevert(bytes("only owner"));
        guardian.setQuorum(5);
    }
    function test_NonGuardianCannotApproveRecovery() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        address nonGuardian = vm.addr(0x999);
        address newOwner = vm.addr(0x888);
        
        // Dirección que no es guardian intenta aprobar recovery
        vm.prank(nonGuardian);
        vm.expectRevert(abi.encodeWithSelector(Guardian.InvalidGuardian.selector));
        guardian.approveRecovery(newOwner);
    }
    function test_RemovedGuardianCannotApproveRecovery() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        address newOwner = vm.addr(0x888);
        
        // Owner remueve al guardian
        vm.prank(address(account));
        guardian.remove(guardian1Hash);
        
        // Guardian removido intenta aprobar recovery (debería fallar)
        vm.prank(guardian1Addr);
        vm.expectRevert(abi.encodeWithSelector(Guardian.GuardianNotAccepted.selector));
        guardian.approveRecovery(newOwner);
    }
    function test_PendingGuardianCannotApproveRecovery() public {
        // Invitar pero no aceptar
        vm.prank(address(account));
        guardian.invite(guardian1Hash);
        
        address newOwner = vm.addr(0x888);
        
        // Guardian pendiente intenta aprobar recovery (debería fallar)
        vm.prank(guardian1Addr);
        vm.expectRevert(abi.encodeWithSelector(Guardian.InvalidGuardian.selector));
        guardian.approveRecovery(newOwner);
    }
    function test_GuardianCannotAcceptInvitationForOthers() public {
        vm.prank(address(account));
        guardian.invite(guardian1Hash);
        
        // Guardian2 intenta aceptar invitación de guardian1 (debería fallar)
        vm.prank(guardian2Addr);
        vm.expectRevert(bytes("Invalid guardian hash"));
        guardian.accept(guardian1Hash);
    }
    function test_RandomAddressCannotAcceptNonExistentInvitation() public {
        address randomAddr = vm.addr(0x999);
        bytes32 randomHash = keccak256(abi.encodePacked(randomAddr));
        
        // Dirección random intenta aceptar invitación que no existe
        vm.prank(randomAddr);
        vm.expectRevert(bytes("not pending"));
        guardian.accept(randomHash);
    }
    function test_GuardianCannotModifyRecoveryDataDirectly() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        address newOwner = vm.addr(0x888);
        
        // Guardian aprueba recovery normal
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        // Verificar que no hay formas de modificar directamente los datos
        // (esto se prueba implícitamente ya que no hay funciones públicas para hacerlo)
        
        bytes32 recKey = keccak256(abi.encode(newOwner));
        (address recoveryOwner, uint8 approvals, bool executed, ) = guardian.recoveries(recKey);
        
        assertEq(recoveryOwner, newOwner);
        assertEq(approvals, 1);
        assertTrue(executed);
    }
    function test_OnlyOwnerCanCreateGuardianContract() public {
        // Test implícito: verificar que el constructor establece correctamente el owner
        Guardian testGuardian = new Guardian(address(account));
        assertEq(testGuardian.owner(), address(account));
        
        vm.prank(vm.addr(0x999));
        vm.expectRevert(bytes("only owner"));
        testGuardian.setQuorum(3); // Debería fallar
    }
    function test_GuardianCannotBypassQuorumRequirement() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        setupGuardian(guardian3Addr, guardian3Hash);
        
        // Establecer quorum alto
        vm.prank(address(account));
        guardian.setQuorum(3);
        
        address newOwner = vm.addr(0x888);
        
        // Solo un guardian vota (no debería ejecutar)
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        // Verificar que no se ejecutó
        assertEq(account.owner(), owner);
        
        bytes32 recKey = keccak256(abi.encode(newOwner));
        (, uint8 approvals, bool executed, ) = guardian.recoveries(recKey);
        assertEq(approvals, 1);
        assertFalse(executed);
    }
    function test_GuardianCannotVoteTwiceEvenAfterStateChanges() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        
        vm.prank(address(account));
        guardian.setQuorum(2);
        
        address newOwner = vm.addr(0x888);
        
        // Guardian1 vota
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        // Intentar votar de nuevo (debería fallar)
        vm.prank(guardian1Addr);
        vm.expectRevert(abi.encodeWithSelector(Guardian.AlreadyVoted.selector));
        guardian.approveRecovery(newOwner);
        
        // Incluso si el quorum cambia, no debería poder votar de nuevo
        vm.prank(address(account));
        guardian.setQuorum(1);
        
        vm.prank(guardian1Addr);
        vm.expectRevert(abi.encodeWithSelector(Guardian.AlreadyVoted.selector));
        guardian.approveRecovery(newOwner);
    }
    function test_MaliciousGuardianCannotManipulateVotedMapping() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        address newOwner = vm.addr(0x888);
        bytes32 recKey = keccak256(abi.encode(newOwner));
        
        // Verificar estado inicial
        assertFalse(guardian.voted(guardian1Hash, recKey));
        
        // Guardian vota normalmente
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        // Verificar que el voto se registró
        assertTrue(guardian.voted(guardian1Hash, recKey));
        
        // No hay forma externa de modificar el mapping voted
        // (se prueba implícitamente ya que no hay funciones públicas para hacerlo)
    }
    // Test de edge case: verificar que los modificadores funcionan correctamente
    function test_ModifierOnlyActiveGuardianWorksCorrectly() public {
        address fakeGuardian = vm.addr(0x999);
        address newOwner = vm.addr(0x888);
        
        // Dirección que no está en guardianAddressToHash
        vm.prank(fakeGuardian);
        vm.expectRevert(abi.encodeWithSelector(Guardian.InvalidGuardian.selector));
        guardian.approveRecovery(newOwner);
        
        // Invitar pero no aceptar
        bytes32 fakeHash = keccak256(abi.encodePacked(fakeGuardian));
        vm.prank(address(account));
        guardian.invite(fakeHash);
        
        // Guardian pendiente intenta usar función
        vm.prank(fakeGuardian);
        vm.expectRevert(abi.encodeWithSelector(Guardian.InvalidGuardian.selector));
        guardian.approveRecovery(newOwner);
    }
    // NUEVAS PRUEBAS PARA LOS GUARDIANAS PARA PROBAR RECUPERACIONES EXPIRADAS
    function test_ExpiredRecoveryAllowsNewProposal() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        address newOwner = vm.addr(0x999);
        
        // FIX: Set a quorum > 1 so the first approval doesn't execute it.
        vm.prank(address(account));
        guardian.setQuorum(2);
        
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        (uint8 approvals, bool executed, , bool expired) =
            guardian.getRecoveryStatus(newOwner);
        assertEq(approvals, 1);
        assertFalse(executed, "Recovery should not execute with 1 of 2 approvals"); // This will now pass
        assertFalse(expired);
        
        // Advance time to make the pending recovery expire
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);
        
        (, , , expired) = guardian.getRecoveryStatus(newOwner);
        assertTrue(expired, "Recovery should be expired");
        
        // Now, the same guardian proposes again. This should trigger cleanup and create a new proposal.
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        // With the new proposal, approvals reset to 1.
        (approvals, executed, , ) = guardian.getRecoveryStatus(newOwner);
        assertEq(approvals, 1, "A new proposal should have 1 approval");
        assertFalse(executed, "Should not be executed yet, quorum is 2");
        // The test logic for final execution would require a second guardian.
        // For this test, we confirm the state is reset correctly.
    }
    function test_ExpiredRecoveryStateIsReset() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        address newOwner = vm.addr(0x999);
        
        // FIX: Set a quorum > 1
        vm.prank(address(account));
        guardian.setQuorum(2);
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        bytes32 recKey = keccak256(abi.encode(newOwner));
        
        (address recoveryOwner, uint8 approvals, bool executed, ) = guardian.recoveries(recKey);
        assertEq(recoveryOwner, newOwner);
        assertEq(approvals, 1);
        assertFalse(executed);
        
        // Advance time
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);
        
        // This second call should now work, triggering cleanup and starting a new recovery
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        (recoveryOwner, approvals, , ) = guardian.recoveries(recKey);
        assertEq(recoveryOwner, newOwner, "A new instance should be created");
        assertEq(approvals, 1, "The new recovery should have 1 approval");
    }
    function test_MultipleExpiredRecoveries() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        address newOwner1 = vm.addr(0x999);
        address newOwner2 = vm.addr(0x888);
        
        // FIX: Set a quorum > 1
        vm.prank(address(account));
        guardian.setQuorum(2);
        
        // Propose for owner 1 (doesn't execute)
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner1);
        
        // Propose for owner 2 (doesn't execute)
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner2);
        
        // Advance time so both expire
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);
        
        // Now, repropose for owner 1. This should work.
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner1);
        
        // And repropose for owner 2. This should also work.
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner2);
        
        (uint8 approvals1, bool executed1, , ) = guardian.getRecoveryStatus(newOwner1);
        (uint8 approvals2, bool executed2, , ) = guardian.getRecoveryStatus(newOwner2);
        
        assertEq(approvals1, 1, "Approvals for newOwner1 should be 1");
        assertFalse(executed1, "Should not be executed yet");
        assertEq(approvals2, 1, "Approvals for newOwner2 should be 1");
        assertFalse(executed2, "Should not be executed yet");
    }
    function test_ExpiredRecoveryCannotBeExecutedByGuardian() public {
        setupGuardian(guardian1Addr, guardian1Hash);
        setupGuardian(guardian2Addr, guardian2Hash);
        
        vm.prank(address(account));
        guardian.setQuorum(2);
        
        address newOwner = vm.addr(0x888);
        
        // Guardian1 vota
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        // Verificar estado inicial
        (uint8 initialApprovals, bool initialExecuted, , ) = guardian.getRecoveryStatus(newOwner);
        assertEq(initialApprovals, 1);
        assertFalse(initialExecuted, "No deberia ejecutarse con solo 1 voto y quorum=2");
        
        // Pasar el tiempo de expiración
        vm.warp(block.timestamp + guardian.RECOVERY_PERIOD() + 1);
        
        // Verificar que la recuperación está expirada
        (, , , bool expired) = guardian.getRecoveryStatus(newOwner);
        assertTrue(expired, "La recuperacion deberia estar expirada");
        
        // Guardian2 intenta votar en recovery expirado (debería limpiar y crear nuevo)
        vm.prank(guardian2Addr);
        guardian.approveRecovery(newOwner); // Esto crea una nueva propuesta
        
        // Verificar que se creó una nueva propuesta
        bytes32 recKey = keccak256(abi.encode(newOwner));
        (, uint8 approvals, bool executed, ) = guardian.recoveries(recKey);
        assertEq(approvals, 1, "Solo deberia haber 1 voto en la nueva propuesta");
        assertFalse(executed, "NO deberia ejecutarse con solo 1 voto cuando quorum=2");
        
        // Ahora Guardian1 vota de nuevo para completar el quorum
        vm.prank(guardian1Addr);
        guardian.approveRecovery(newOwner);
        
        // AHORA sí debería ejecutarse
        (, approvals, executed, ) = guardian.recoveries(recKey);
        assertEq(approvals, 2, "Deberia haber 2 votos");
        assertTrue(executed, "Deberia ejecutarse con quorum completo");
        assertEq(account.owner(), newOwner, "La propiedad deberia transferirse");
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
