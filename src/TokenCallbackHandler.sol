// SPDX-License-Identifier: GPL-3.0
// Define la licencia del contrato como GPL-3.0

pragma solidity ^0.8.24;
// Especifica la versión del compilador de Solidity requerido

/* solhint-disable no-empty-blocks */
// Desactiva la regla de solhint para bloques vacíos

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
// Importa la interfaz para introspección de contratos

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
// Importa la interfaz para manejar callbacks de tokens ERC721

import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
// Importa la interfaz para manejar callbacks de tokens ERC1155

/**
 * Token callback handler.
 * Manejador de callbacks para tokens.
 * Permite que las cuentas reciban estos tokens.
 */
abstract contract TokenCallbackHandler is IERC721Receiver, IERC1155Receiver {

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
        // Devuelve el selector de la función para ERC721
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
        // Devuelve el selector de la función para ERC1155
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
        // Devuelve el selector de la función para ERC1155 en lotes
    }

    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
        // Verifica si el contrato soporta las interfaces especificadas
    }
}
