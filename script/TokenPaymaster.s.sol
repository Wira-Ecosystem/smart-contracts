// SPDX-License-Identifier: GPL-3.0
// Define la licencia del contrato como GPL-3.0

pragma solidity ^0.8.24;
// Especifica la versión del compilador de Solidity requerido

import {Script, console} from "forge-std/Script.sol";
// Importa utilidades de Forge para scripts

import {TokenPaymaster, IERC20Metadata, IERC20} from "../src/archived/TokenPaymaster.sol";
import {UniswapHelper, ISwapRouter} from "../src/archived/utils/UniswapHelper.sol";
import {OracleHelper} from "../src/archived/utils/OracleHelper.sol";
// Importa el contrato TokenPaymaster

import {MockOracle} from "../src/archived/utils/MockOracle.sol";
// Importa el contrato MockOracle para precios simulados

import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";
// Importa la interfaz para el EntryPoint

contract TokenPaymasterScript is Script {
    // EntryPoint contract (v0.7)
    IEntryPoint constant ENTRYPOINT =
        IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    // Dirección del contrato EntryPoint

    // Wormhole contracts
    mapping(uint256 => address) private cores;
    // Mapeo para las direcciones de los núcleos de Wormhole

    mapping(uint256 => address) private relayers;
    // Mapeo para las direcciones de los relayers de Wormhole

    mapping(uint256 => address) private bridges;
    // Mapeo para las direcciones de los puentes de Wormhole

    mapping(uint256 => address) private gasTokens;
    // Mapeo para las direcciones de los tokens de gas

    function run() external {
        //Wormhole OP sepolia contracts
        cores[11155420] = 0x31377888146f3253211EFEf5c676D41ECe7D58Fe;
        relayers[11155420] = 0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE;
        bridges[11155420] = 0x99737Ec4B815d816c49A385943baf0380e75c0Ac;
        gasTokens[11155420] = 0x50aA08060b2038EB86F46E3262096097813A3dcf;
        // Configuración para la red OP Sepolia

        // Wormhole Polygon Amoy contracts
        cores[80002] = 0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35;
        relayers[80002] = 0x362fca37E45fe1096b42021b543f462D49a5C8df;
        bridges[80002] = 0xC7A204bDBFe983FCD8d8E61D02b475D4073fF97e;
        // Configuración para la red Polygon Amoy

        // Wormhole Base Sepolia contracts
        cores[84532] = 0x79A1027a6A159502049F10906D333EC57E95F083;
        relayers[84532] = 0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE;
        bridges[84532] = 0x86F55A04690fd7815A3D802bD587e83eA888B239;
        gasTokens[84532] = 0xB6cbBB295b9cDad7b00A887207d41066ACF47669;
        // Configuración para la red Base Sepolia

        // Wormhole Arbitrum Sepolia contracts
        cores[421614] = 0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35;
        relayers[421614] = 0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470;
        bridges[421614] = 0xC7A204bDBFe983FCD8d8E61D02b475D4073fF97e;
        gasTokens[421614] = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;

        require(cores[block.chainid] != address(0), "Chain not supported");
        // Verifica que la cadena esté soportada

        require(gasTokens[block.chainid] != address(0), "Token not exists on chain");
        // Verifica que el token de gas exista en la cadena

        IERC20Metadata gasToken = IERC20Metadata(gasTokens[block.chainid]);
        // Token usado para pagar el gas

        IERC20 wrappedNative = IERC20(vm.envAddress("W_NATIVE"));
        // Token nativo envuelto para intercambiar

        ISwapRouter swapRouter = ISwapRouter(vm.envAddress("UNISWAP_ROUTER"));
        // Router de Uniswap para intercambiar tokens

        TokenPaymaster.TokenPaymasterConfig memory tokenPaymasterConfig = TokenPaymaster.TokenPaymasterConfig({
            priceMarkup: 1e26,
            // Aumento de precio del 100%

            minEntryPointBalance: 0.00001 ether,
            // Balance mínimo antes de intercambiar tokens

            refundPostopCost: 40000,
            // Costo de gas para operaciones de reembolso

            priceMaxAge: 86400
            // Precio válido por 1 día
        });

        vm.startBroadcast(); // Start broadcasting transactions

        MockOracle ethOracle = new MockOracle(200000000000, 8);
        // Oracle simulado para ETH/USD

        MockOracle tokenOracle = new MockOracle(100000000, 8);
        // Oracle simulado para token/USD

        OracleHelper.OracleHelperConfig memory oracleHelperConfig = OracleHelper.OracleHelperConfig({
            cacheTimeToLive: 300,
            // Cache de precios por 5 minutos

            maxOracleRoundAge: 1800,
            // Edad máxima de datos del oracle (30 minutos)

            nativeOracle: ethOracle,
            nativeOracleReverse: false,
            // Indica si el oracle devuelve token/ETH en lugar de ETH/token

            priceUpdateThreshold: 1e25,
            // Actualiza el precio si cambia en un 10%

            tokenOracle: tokenOracle,
            tokenOracleReverse: false,
            // Indica si el oracle devuelve ETH/token en lugar de token/ETH

            tokenToNativeOracle: false
            // Indica si se usa un oracle directo token/nativo
        });

        UniswapHelper.UniswapHelperConfig memory uniswapHelperConfig = UniswapHelper.UniswapHelperConfig({
            minSwapAmount: 0.01 ether,
            // Monto mínimo para intercambiar

            slippage: 5,
            // Tolerancia de deslizamiento del 5%

            uniswapPoolFee: 3000
            // Tarifa de pool del 0.3%
        });

        TokenPaymaster tokenPaymaster = new TokenPaymaster(
            gasToken,
            12,
            // Decimales del token de gas para USDT

            ENTRYPOINT,
            wrappedNative,
            swapRouter,
            tokenPaymasterConfig,
            oracleHelperConfig,
            uniswapHelperConfig,
            msg.sender,
            // Propietario del contrato

            relayers[block.chainid],
            bridges[block.chainid],
            cores[block.chainid]
        );

        tokenPaymaster.updateCachedPrice(false);
        // Actualiza el precio en caché

        console.log("TokenPaymaster deployed at:", address(tokenPaymaster));
        // Imprime la dirección del contrato desplegado

        vm.stopBroadcast();
        // Detiene la transmisión de transacciones
    }
}