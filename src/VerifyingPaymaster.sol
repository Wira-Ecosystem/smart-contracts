// SPDX-License-Identifier: GPL-3.0
// Define la licencia del contrato como GPL-3.0

pragma solidity ^0.8.24;
// Especifica la versión del compilador de Solidity requerido

/* solhint-disable reason-string */
/* solhint-disable no-inline-assembly */
// Desactiva ciertas reglas de solhint para este archivo

import "@account-abstraction/core/BasePaymaster.sol";
// Importa la clase base para Paymasters

import "@account-abstraction/core/UserOperationLib.sol";
// Importa la librería para operaciones de usuario

import "@account-abstraction/core/Helpers.sol";
// Importa funciones auxiliares para operaciones de usuario

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// Importa utilidades para firmas digitales ECDSA

import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
// Importa utilidades para manejar hashes de mensajes

/**
 * A sample paymaster that uses external service to decide whether to pay for the UserOp.
 * Paymaster que utiliza un servicio externo para decidir si paga por la operación de usuario.
 * Confía en un firmante externo para validar la transacción.
 */
contract VerifyingPaymaster is BasePaymaster {

    using UserOperationLib for PackedUserOperation;
    // Habilita el uso de funciones de la librería UserOperationLib

    address public immutable verifyingSigner;
    // Dirección del firmante externo, inmutable

    uint256 private constant VALID_TIMESTAMP_OFFSET = PAYMASTER_DATA_OFFSET;
    // Offset para el timestamp válido en los datos del Paymaster

    uint256 private constant SIGNATURE_OFFSET = VALID_TIMESTAMP_OFFSET + 64;
    // Offset para la firma en los datos del Paymaster

    constructor(IEntryPoint _entryPoint, address _verifyingSigner) BasePaymaster(_entryPoint) {
        verifyingSigner = _verifyingSigner;
        // Configura el firmante externo
    }

    /**
     * return the hash we're going to sign off-chain (and validate on-chain)
     * this method is called by the off-chain service, to sign the request.
     * it is called on-chain from the validatePaymasterUserOp, to validate the signature.
     * note that this signature covers all fields of the UserOperation, except the "paymasterAndData",
     * which will carry the signature itself.
     */
    function getHash(PackedUserOperation calldata userOp, uint48 validUntil, uint48 validAfter)
    public view returns (bytes32) {
        address sender = userOp.getSender();
        // Obtiene el remitente de la operación de usuario

        return
            keccak256(
            abi.encode(
                sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.preVerificationGas,
                block.chainid,
                address(this),
                validUntil,
                validAfter
            )
        );
        // Calcula el hash de la operación de usuario
    }

    /**
     * verify our external signer signed this request.
     * the "paymasterAndData" is expected to be the paymaster and a signature over the entire request params
     * paymasterAndData[:20] : address(this)
     * paymasterAndData[20:84] : abi.encode(validUntil, validAfter)
     * paymasterAndData[84:] : signature
     */
    function _validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 /*userOpHash*/, uint256 requiredPreFund)
    internal view override returns (bytes memory context, uint256 validationData) {
        (requiredPreFund);
        // Valida la operación de usuario

        (uint48 validUntil, uint48 validAfter, bytes calldata signature) = parsePaymasterAndData(userOp.paymasterAndData);
        require(signature.length == 64 || signature.length == 65, "VerifyingPaymaster: invalid signature length in paymasterAndData");
        // Asegura que la longitud de la firma sea válida

        bytes32 opHash = getHash(userOp, validUntil, validAfter);
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(opHash);
        // Convierte el hash a formato firmado por Ethereum

        if (verifyingSigner != ECDSA.recover(hash, signature)) {
            return ("", _packValidationData(true, validUntil, validAfter));
            // Devuelve datos de validación si la firma no es válida
        }

        return ("", _packValidationData(false, validUntil, validAfter));
        // Devuelve datos de validación si la firma es válida
    }

    function parsePaymasterAndData(bytes calldata paymasterAndData) public pure returns (uint48 validUntil, uint48 validAfter, bytes calldata signature) {
        (validUntil, validAfter) = abi.decode(paymasterAndData[VALID_TIMESTAMP_OFFSET :], (uint48, uint48));
        signature = paymasterAndData[SIGNATURE_OFFSET :];
        // Decodifica los datos del Paymaster
    }
}
