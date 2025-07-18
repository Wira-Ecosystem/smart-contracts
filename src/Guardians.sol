// SPDX-License-Identifier:  GPL-3.0
// Define la licencia del contrato como GPL-3.0

pragma solidity ^0.8.24;
// Especifica la versión del compilador de Solidity requerida

interface ISimpleAccount {
    function executeRecovery(address newOwner) external;
    // Define una interfaz con una función para ejecutar la recuperación de cuenta
}

contract Guardian {
    // Define el contrato principal llamado Guardian

    enum Status {
        NONE,
        PENDING,
        ACCEPTED,
        REJECTED
    }
    // Enum para representar el estado de un guardián

    struct Recovery {
        address newOwner;
        uint8 approvals;
        bool executed;
        uint256 proposedAt;
    }
    // Estructura para almacenar información sobre una recuperación

    struct GuardianInfo {
        Status state;
        uint40 invitedAt;
    }
    // Estructura para almacenar información sobre un guardián

    address public immutable owner;
    // Dirección del propietario del contrato, inmutable

    uint8 public requiredApprovals = 1;
    // Número de aprobaciones requeridas para una recuperación

    uint256 public constant RECOVERY_PERIOD = 3 days;
    // Periodo de tiempo constante para la recuperación

    mapping(bytes32 => GuardianInfo) public guardians;
    // Mapeo para almacenar información de guardianes por su hash

    mapping(bytes32 => Recovery) public recoveries;
    // Mapeo para almacenar información de recuperaciones por su hash

    mapping(bytes32 => mapping(bytes32 => bool)) public voted;
    // Mapeo para rastrear votos de guardianes en recuperaciones

    mapping(address => bytes32) public guardianAddressToHash;
    // Mapeo para asociar direcciones de guardianes con su hash

    event GuardianInvited(bytes32 indexed did);
    // Evento emitido cuando se invita a un guardián

    event GuardianAccepted(
        bytes32 indexed did,
        address indexed guardianAddress
    );
    // Evento emitido cuando un guardián acepta la invitación

    event GuardianRemoved(bytes32 indexed did);
    // Evento emitido cuando se elimina un guardián

    event QuorumChanged(uint8 newQuorum);
    // Evento emitido cuando se cambia el quórum

    event RecoveryProposed(address indexed newOwner, uint256 deadline);
    // Evento emitido cuando se propone una recuperación

    event RecoveryApproved(address indexed newOwner, bytes32 indexed guardian);
    // Evento emitido cuando un guardián aprueba una recuperación

    event RecoveryExecuted(address indexed newOwner);
    // Evento emitido cuando se ejecuta una recuperación

    error NotAuthorized();
    // Error lanzado cuando un usuario no está autorizado

    error InvalidGuardian();
    // Error lanzado cuando un guardián no es válido

    error RecoveryExpired();
    // Error lanzado cuando el periodo de recuperación ha expirado

    error AlreadyVoted();
    // Error lanzado cuando un guardián ya ha votado

    error GuardianNotAccepted();
    // Error lanzado cuando un guardián no ha sido aceptado

    constructor(address _owner) {
        owner = _owner;
        // Constructor que inicializa el propietario del contrato
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        // Modificador que asegura que solo el propietario puede ejecutar la función
        _;
    }

    modifier onlyActiveGuardian() {
        bytes32 guardianHash = guardianAddressToHash[msg.sender];
        if (guardianHash == bytes32(0)) revert InvalidGuardian();
        // Verifica que el remitente sea un guardián válido

        if (guardians[guardianHash].state != Status.ACCEPTED)
            revert GuardianNotAccepted();
        // Verifica que el guardián esté en estado aceptado

        _;
    }

    function invite(bytes32 guardianHash) external onlyOwner {
        require(guardianHash != bytes32(0), "zero");
        // Asegura que el hash del guardián no sea cero

        GuardianInfo storage g = guardians[guardianHash];
        require(g.state == Status.NONE, "exists");
        // Asegura que el guardián no exista previamente

        g.state = Status.PENDING;
        g.invitedAt = uint40(block.timestamp);
        // Actualiza el estado del guardián y registra el tiempo de invitación

        emit GuardianInvited(guardianHash);
        // Emite un evento de invitación
    }

    function accept(bytes32 guardianHash) external {
        GuardianInfo storage g = guardians[guardianHash];
        require(g.state == Status.PENDING, "not pending");
        // Asegura que el estado del guardián sea pendiente

        bytes32 expectedHash = keccak256(abi.encodePacked(msg.sender));
        require(guardianHash == expectedHash, "Invalid guardian hash");
        // Verifica que el hash proporcionado coincida con el esperado

        g.state = Status.ACCEPTED;
        guardianAddressToHash[msg.sender] = guardianHash;
        // Actualiza el estado del guardián y asocia la dirección con el hash

        emit GuardianAccepted(guardianHash, msg.sender);
        // Emite un evento de aceptación
    }

    function remove(bytes32 guardianHash) external onlyOwner {
        delete guardians[guardianHash];
        // Elimina la información del guardián

        emit GuardianRemoved(guardianHash);
        // Emite un evento de eliminación
    }

    function setQuorum(uint8 q) external onlyOwner {
        require(q > 0, "zero");
        // Asegura que el quórum sea mayor a cero

        requiredApprovals = q;
        // Actualiza el número de aprobaciones requeridas

        emit QuorumChanged(q);
        // Emite un evento de cambio de quórum
    }

    function isGuardian(bytes32 h) external view returns (bool) {
        return guardians[h].state == Status.ACCEPTED;
        // Devuelve verdadero si el estado del guardián es aceptado
    }

    function approveRecovery(address newOwner) external onlyActiveGuardian {
        require(newOwner != address(0), "Invalid new owner");
        // Asegura que la nueva dirección del propietario no sea cero

        bytes32 guardianHash = guardianAddressToHash[msg.sender];
        bytes32 recKey = keccak256(abi.encode(newOwner));
        // Calcula el hash de recuperación basado en la nueva dirección del propietario

        if (voted[guardianHash][recKey]) revert AlreadyVoted();
        // Verifica que el guardián no haya votado previamente

        Recovery storage r = recoveries[recKey];

        if (r.newOwner == address(0)) {
            r.newOwner = newOwner;
            r.proposedAt = block.timestamp;
            // Inicializa la recuperación si no existe previamente

            emit RecoveryProposed(newOwner, block.timestamp + RECOVERY_PERIOD);
            // Emite un evento de propuesta de recuperación
        }

        if (block.timestamp > r.proposedAt + RECOVERY_PERIOD) {
            revert RecoveryExpired();
            // Lanza un error si el periodo de recuperación ha expirado
        }

        voted[guardianHash][recKey] = true;
        r.approvals += 1;
        // Marca el voto del guardián y aumenta el número de aprobaciones

        emit RecoveryApproved(newOwner, guardianHash);
        // Emite un evento de aprobación de recuperación

        if (!r.executed && r.approvals >= requiredApprovals) {
            r.executed = true;
            ISimpleAccount(owner).executeRecovery(newOwner);
            // Ejecuta la recuperación si se cumplen las condiciones

            emit RecoveryExecuted(newOwner);
            // Emite un evento de ejecución de recuperación
        }
    }

    function getRecoveryStatus(
        address newOwner
    )
        external
        view
        returns (uint8 approvals, bool executed, uint256 deadline, bool expired)
    {
        bytes32 recKey = keccak256(abi.encode(newOwner));
        Recovery storage r = recoveries[recKey];

        return (
            r.approvals,
            // Devuelve el número de aprobaciones

            r.executed,
            // Devuelve si la recuperación fue ejecutada

            r.proposedAt + RECOVERY_PERIOD,
            // Devuelve el tiempo límite para la recuperación

            block.timestamp > r.proposedAt + RECOVERY_PERIOD
            // Devuelve si el periodo de recuperación ha expirado
        );
    }

    function getGuardianByAddress(
        address guardianAddr
    ) external view returns (bytes32) {
        return guardianAddressToHash[guardianAddr];
        // Devuelve el hash asociado a la dirección del guardián
    }
}
