// SPDX-License-Identifier: GPL-3.0
// Define la licencia del contrato como GPL-3.0

pragma solidity ^0.8.24;
// Especifica la versión del compilador de Solidity requerido

import "@openzeppelin/contracts/utils/Create2.sol";
// Importa utilidades para crear contratos usando Create2

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// Importa la implementación de proxy ERC1967

import "./SimpleAccount.sol";
// Importa el contrato SimpleAccount

import "./Guardians.sol";
// Importa el contrato Guardians

/**
 * A sample factory contract for SimpleAccount
 * Contrato de fábrica para crear instancias de SimpleAccount
 * Permite crear cuentas y guardianes asociados
 */
contract SimpleAccountFactory {
    IEntryPoint public immutable entryPoint;
    // Dirección del EntryPoint, inmutable

    address public fcOwner;
    // Dirección del propietario de la fábrica

    SimpleAccount public accountImplementation;
    // Implementación base de SimpleAccount

    mapping(address => address) public guardianOf;
    // Mapeo para asociar cuentas con sus guardianes

    uint256 public gasToDebt = 0;
    // Variable para almacenar la deuda de gas

    event AccountCreated(
        uint256 chainid,
        address account
    );
    // Evento emitido cuando se crea una cuenta

    event GuardianCreated(address indexed account, address indexed guardian);
    // Evento emitido cuando se crea un guardián

    modifier onlyOwner {
        require(msg.sender == fcOwner, "Only owner");
        // Modificador que asegura que solo el propietario puede ejecutar la función
        _;
    }

    constructor(IEntryPoint _entryPoint, address _owner) {
        fcOwner = _owner;
        // Configura el propietario de la fábrica

        entryPoint = _entryPoint;
        // Configura el EntryPoint
    }

    function initialize(address _tokenPaymaster) external onlyOwner {
        require(address(accountImplementation) == address(0), "Already initialized");
        // Previene doble inicialización

        accountImplementation = new SimpleAccount(entryPoint, _tokenPaymaster);
        // Crea una nueva instancia de SimpleAccount como implementación base

        emit AccountCreated(block.chainid, address(accountImplementation));
        // Emite un evento de creación de cuenta
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     */
    function createAccount(address owner,uint256 salt) public returns (SimpleAccount ret) {
        require(owner != address(0), "Owner cannot be zero address");
        // Asegura que el propietario no sea la dirección cero

        address addr = getAddress(owner, salt);
        // Calcula la dirección de la cuenta usando Create2

        uint256 codeSize = addr.code.length;
        if (codeSize > 0) {
            return SimpleAccount(payable(addr));
            // Devuelve la cuenta si ya está desplegada
        }

        ret = SimpleAccount(payable(new ERC1967Proxy{salt : bytes32(salt)}(
                address(accountImplementation),
                abi.encodeCall(SimpleAccount.initialize, (owner, address(this)))
            )));
        // Crea una nueva cuenta usando un proxy ERC1967

        ret.setCreateDebt(gasToDebt);
        // Configura la deuda de gas en la cuenta creada
    }

    function createGuardianForAccount(
        address account,
        uint256 salt
    ) external returns (address) {
        require(account != address(0), "Invalid account");
        // Asegura que la cuenta no sea la dirección cero

        require(guardianOf[account] == address(0), "Guardian already exists");
        // Asegura que la cuenta no tenga un guardián existente

        require(
            SimpleAccount(payable(account)).isThisASimpleAccountContract(),
            "Not a SimpleAccount"
        );
        // Asegura que la cuenta sea una instancia válida de SimpleAccount

        bytes32 guardianSalt = keccak256(abi.encodePacked(account, salt));
        Guardian guardianContract = new Guardian{salt: guardianSalt}(account);
        // Crea un nuevo contrato de guardián usando Create2

        SimpleAccount(payable(account)).setGuardian(address(guardianContract));
        // Configura el guardián en la cuenta

        guardianOf[account] = address(guardianContract);
        // Actualiza el mapeo de guardianes

        emit GuardianCreated(account, address(guardianContract));
        // Emite un evento de creación de guardián

        return address(guardianContract);
        // Devuelve la dirección del guardián creado
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     */
    function getAddress(address owner,uint256 salt) public view returns (address) {
        return Create2.computeAddress(bytes32(salt), keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    address(accountImplementation),
                    abi.encodeCall(SimpleAccount.initialize, (owner, address(this)))
                )
            )
        ));
        // Calcula la dirección contrafactual de una cuenta
    }

    function getGuardianAddress(
        address account,
        uint256 salt
    ) public view returns (address) {
        bytes32 guardianSalt = keccak256(abi.encodePacked(account, salt));
        return
            Create2.computeAddress(
                guardianSalt,
                keccak256(
                    abi.encodePacked(
                        type(Guardian).creationCode,
                        abi.encode(account)
                    )
                )
            );
        // Calcula la dirección contrafactual de un guardián
    }

    function setGasToDebt(uint256 _gasToDebt) external onlyOwner {
        gasToDebt = _gasToDebt;
        // Configura la deuda de gas
    }

    /**
     * Add stake for this factory.
     * This method can also carry eth value to add to the current stake.
     * @param unstakeDelaySec - The unstake delay for this factory. Can only be increased.
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
        // Añade participación para la fábrica
    }

    /**
     * Unlock the stake, in order to withdraw it.
     * The factory can't serve requests once unlocked, until it calls addStake again
     */
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
        // Desbloquea la participación
    }

    /**
     * Withdraw the entire factory's stake.
     * stake must be unlocked first (and then wait for the unstakeDelay to be over)
     * @param withdrawAddress - The address to send withdrawn value.
     */
    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
        // Retira la participación desbloqueada
    }
}
