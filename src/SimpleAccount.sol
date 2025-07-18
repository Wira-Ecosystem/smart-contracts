// SPDX-License-Identifier: GPL-3.0
// Define la licencia del contrato como GPL-3.0

pragma solidity ^0.8.24;
// Especifica la versión del compilador de Solidity requerido

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */
// Desactiva ciertas reglas de solhint para este archivo

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// Importa utilidades para firmas digitales ECDSA

import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
// Importa utilidades para manejar hashes de mensajes

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
// Importa funcionalidad para contratos inicializables

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
// Importa funcionalidad para contratos actualizables usando UUPS

import "@account-abstraction/core/BaseAccount.sol";
// Importa la clase base para cuentas abstractas

import "@account-abstraction/core/Helpers.sol";
// Importa funciones auxiliares para cuentas abstractas

import "./TokenCallbackHandler.sol";
// Importa el manejador de callbacks para tokens

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// Importa utilidades para manejar tokens ERC20 de forma segura

import "./Guardians.sol";
// Importa el contrato de guardianes

/**
  * minimal account.
  * Este es un ejemplo de cuenta mínima.
  * Tiene métodos para ejecutar transacciones y manejar ETH.
  * Tiene un único firmante que puede enviar solicitudes a través del EntryPoint.
  */
contract SimpleAccount is BaseAccount, TokenCallbackHandler, UUPSUpgradeable, Initializable {
    address public owner;
    // Dirección del propietario de la cuenta

    IEntryPoint private immutable _entryPoint;
    // Dirección del EntryPoint, inmutable

    address public guardian;
    // Dirección del contrato de guardianes

    address public factory;
    // Dirección de la fábrica asociada

    address public immutable tokenPaymaster;
    // Dirección del Paymaster de tokens, inmutable

    using SafeERC20 for IERC20;
    // Habilita el uso de funciones seguras para tokens ERC20

    mapping(bytes32 => string) private _streamOf;
    // Mapeo para asociar hashes de ID con streams

    error GuardianNotConfigurado();
    // Error lanzado si el guardián no está configurado

    bool public immutable isThisASimpleAccountContract = true;
    // Bandera inmutable para identificar el contrato

    bool public letCollectOnDeliver;
    // Bandera para permitir la recolección de gas en transferencias

    uint256 public createDebt;
    // Variable para almacenar deuda creada

    event SimpleAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    // Evento emitido cuando se inicializa la cuenta

    event OwnerRecovered(address indexed newOwner);
    // Evento emitido cuando se recupera el propietario

    event StreamRegistered(bytes32 indexed idHash, string streamId);
    // Evento emitido cuando se registra un stream

    modifier onlyOwner() {
        _onlyOwner();
        // Modificador que asegura que solo el propietario puede ejecutar la función
       _;
    }

    modifier onlyFactoryOrPaymaster() {
        require(msg.sender == tokenPaymaster || msg.sender == factory, "Only factory or paymaster");
        // Modificador que asegura que solo la fábrica o el Paymaster pueden ejecutar la función
       _;
    }

    modifier onlyGuardianContract() {
        require(msg.sender == address(guardian), "Only guardian contract can call");
        // Modificador que asegura que solo el contrato de guardianes puede ejecutar la función
       _;
    }

    function registerStream(
        bytes32 idHash,
        string calldata streamId
    ) external onlyOwner {
        require(bytes(_streamOf[idHash]).length == 0, "already registered");
        // Asegura que el stream no esté registrado previamente

        _streamOf[idHash] = streamId;
        // Registra el stream

        emit StreamRegistered(idHash, streamId);
        // Emite un evento de registro de stream
    }

    function getStream(bytes32 idHash) external view returns (string memory) {
        return _streamOf[idHash];
        // Devuelve el stream asociado al hash
    }

     function setGuardian(address _guardian) external onlyOwner {
        require(_guardian != address(0), "Guardian cannot be zero address");
        // Asegura que la dirección del guardián no sea cero

        guardian = _guardian;
        // Configura la dirección del guardián
    }

    function getGuardian() external view returns (address) {
        return guardian;
        // Devuelve la dirección del guardián
    }

    function executeRecovery(address newOwner) external {
        if (guardian == address(0)) revert GuardianNotConfigurado();
        // Lanza un error si el guardián no está configurado

        require(msg.sender == guardian, "Only guardian can recover");
        // Asegura que solo el guardián puede ejecutar la recuperación

        require(newOwner != address(0), "New owner cannot be zero");
        // Asegura que la nueva dirección del propietario no sea cero

        owner = newOwner;
        // Actualiza la dirección del propietario

        emit OwnerRecovered(newOwner);
        // Emite un evento de recuperación del propietario
    }

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
        // Devuelve la dirección del EntryPoint
    }

    constructor(IEntryPoint anEntryPoint, address _tokenPaymaster) {
        _entryPoint = anEntryPoint;
        // Configura el EntryPoint

        tokenPaymaster = _tokenPaymaster;
        // Configura el Paymaster de tokens

        _disableInitializers();
        // Desactiva inicializadores
    }

    function _onlyOwner() internal view {
        require(msg.sender == owner || msg.sender == address(this), "only owner");
        // Asegura que el remitente sea el propietario o la cuenta misma
    }

    /**
     * execute a transaction (called directly from owner, or by entryPoint)
     * @param dest destination address to call
     * @param value the value to pass in this call
     * @param func the calldata to pass in this call
     */
    function execute(address dest, uint256 value, bytes calldata func) external {
        _requireFromEntryPointOrOwner();
        // Asegura que la llamada provenga del EntryPoint o del propietario

        _call(dest, value, func);
        // Ejecuta la llamada
    }

    /**
     * execute a sequence of transactions
     * @dev to reduce gas consumption for trivial case (no value), use a zero-length array to mean zero value
     * @param dest an array of destination addresses
     * @param value an array of values to pass to each call. can be zero-length for no-value calls
     * @param func an array of calldata to pass to each call
     */
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) external {
        _requireFromEntryPointOrOwner();
        // Asegura que la llamada provenga del EntryPoint o del propietario

        require(dest.length == func.length && (value.length == 0 || value.length == func.length), "wrong array lengths");
        // Asegura que las longitudes de los arrays sean correctas

        if (value.length == 0) {
            for (uint256 i = 0; i < dest.length; i++) {
                _call(dest[i], 0, func[i]);
                // Ejecuta llamadas sin valor
            }
        } else {
            for (uint256 i = 0; i < dest.length; i++) {
                _call(dest[i], value[i], func[i]);
                // Ejecuta llamadas con valor
            }
        }
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of SimpleAccount must be deployed with the new EntryPoint address, then upgrading
      * the implementation by calling `upgradeTo()`
      * @param anOwner the owner (signer) of this account
     */
    function initialize(address anOwner, address itsFactory) public virtual initializer {
        _initialize(anOwner, itsFactory);
        // Inicializa la cuenta

        emit SimpleAccountInitialized(_entryPoint, owner);
        // Emite un evento de inicialización
    }

    function _initialize(address anOwner, address itsFactory) internal virtual {
        require(anOwner != address(0), "Owner cannot be zero address");
        // Asegura que el propietario no sea la dirección cero

        owner = anOwner;
        // Configura el propietario

        factory = itsFactory;
        // Configura la fábrica

        emit SimpleAccountInitialized(_entryPoint, owner);
        // Emite un evento de inicialización
    }

    // Require the function call went through EntryPoint or owner
    function _requireFromEntryPointOrOwner() internal view {
        require(msg.sender == address(entryPoint()) || msg.sender == owner, "account: not Owner or EntryPoint");
        // Asegura que la llamada provenga del EntryPoint o del propietario
    }

    /// implement template method of BaseAccount
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
    internal override virtual returns (uint256 validationData) {
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        // Convierte el hash a formato firmado por Ethereum

        if (owner != ECDSA.recover(hash, userOp.signature))
            return SIG_VALIDATION_FAILED;
        // Valida la firma del propietario

        return SIG_VALIDATION_SUCCESS;
        // Devuelve éxito en la validación
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        // Realiza una llamada de bajo nivel

        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
                // Revertir si la llamada falla
            }
        }
    }

    /**
     * check current account deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
        // Devuelve el depósito actual de la cuenta en el EntryPoint
    }

    /**
     * deposit more funds for this account in the entryPoint
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value: msg.value}(address(this));
        // Añade fondos al depósito de la cuenta en el EntryPoint
    }

    /**
     * withdraw value from the account's deposit
     * @param withdrawAddress target to send to
     * @param amount to withdraw
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyOwner {
        entryPoint().withdrawTo(withdrawAddress, amount);
        // Retira fondos del depósito de la cuenta
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        _onlyOwner();
        // Autoriza la actualización del contrato
    }

    /// @notice Fallback function to allow the contract to receive Ether.
    /// @dev This function has no function body, making it a default function for receiving Ether.
    /// It is automatically called when Ether is transferred to the contract without any data.
    receive() external payable {}

    /// @notice active/disable option to pay gas of receiving transfers
    function setCollectOnDeliver(bool _collectOnDeliver) external onlyOwner {
        letCollectOnDeliver = _collectOnDeliver;
        // Configura la opción de recolectar gas en transferencias
    }

    /// @notice check create debt to paid (only paymaster or factory)
    function setCreateDebt(uint256 debt) external onlyFactoryOrPaymaster {
        createDebt = debt;
        // Configura la deuda creada
    }
}
