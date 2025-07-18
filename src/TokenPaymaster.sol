// SPDX-License-Identifier: GPL-3.0
// Define la licencia del contrato como GPL-3.0

pragma solidity ^0.8.24;
// Especifica la versión del compilador de Solidity requerido

// Import the required libraries and contracts
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// Importa la interfaz para metadatos de tokens ERC20

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// Importa utilidades para manejar tokens ERC20 de forma segura

import "@account-abstraction/interfaces/IEntryPoint.sol";
// Importa la interfaz para el EntryPoint

import "@account-abstraction/core/BasePaymaster.sol";
// Importa la clase base para Paymasters

import "@account-abstraction/core/Helpers.sol";
// Importa funciones auxiliares para operaciones de usuario

import {SimpleAccount} from "./SimpleAccount.sol";
// Importa el contrato SimpleAccount

import "./transferer/CrossChainTransferer.sol";
// Importa el manejador de transferencias entre cadenas

/// @title Sample ERC-20 Token Paymaster for ERC-4337
/// Paymaster que cubre las tarifas de gas a cambio de tokens ERC20.
/// Permite el reembolso de tokens excedentes si el costo de gas es menor al estimado.
contract TokenPaymaster is BasePaymaster, CrossChainTransferer {

    using UserOperationLib for PackedUserOperation;
    // Habilita el uso de funciones de la librería UserOperationLib

    struct TokenPaymasterConfig {
        uint256 priceMarkup;
        // Porcentaje de aumento aplicado al precio del token

        uint128 minEntryPointBalance;
        // Balance mínimo en el EntryPoint para intercambiar tokens

        uint48 refundPostopCost;
        // Costo estimado de gas para reembolsar tokens después de la transacción

        uint48 priceMaxAge;
        // Edad máxima del precio en caché para validar transacciones
    }

    event ConfigUpdated(TokenPaymasterConfig tokenPaymasterConfig);
    // Evento emitido cuando se actualiza la configuración del Paymaster

    event UserOperationSponsored(address indexed user, uint256 actualTokenCharge, uint256 actualGasCost, uint256 actualTokenPriceWithMarkup);
    // Evento emitido cuando se patrocina una operación de usuario

    event Received(address indexed sender, uint256 value);
    // Evento emitido cuando el contrato recibe Ether

    uint256 private constant PRICE_DENOMINATOR = 1e26;
    // Constante para evitar redondeos en cálculos de precios

    TokenPaymasterConfig public tokenPaymasterConfig;
    // Configuración actual del Paymaster

    /// @notice Initializes the TokenPaymaster contract with the given parameters.
    /// @param _token The ERC20 token used for transaction fee payments.
    /// @param _entryPoint The EntryPoint contract used in the Account Abstraction infrastructure.
    /// @param _wrappedNative The ERC-20 token that wraps the native asset for current chain.
    /// @param _uniswap The Uniswap V3 SwapRouter contract.
    /// @param _tokenPaymasterConfig The configuration for the Token Paymaster.
    /// @param _oracleHelperConfig The configuration for the Oracle Helper.
    /// @param _uniswapHelperConfig The configuration for the Uniswap Helper.
    /// @param _owner The address that will be set as the owner of the contract.
    constructor(
        IERC20Metadata _token,
        uint8 _tokenDecimals,
        IEntryPoint _entryPoint,
        IERC20 _wrappedNative,
        ISwapRouter _uniswap,
        TokenPaymasterConfig memory _tokenPaymasterConfig,
        OracleHelperConfig memory _oracleHelperConfig,
        UniswapHelperConfig memory _uniswapHelperConfig,
        address _owner,
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole
    )
    BasePaymaster(
    _entryPoint
    )
    CrossChainTransferer(
        _token,
        _tokenDecimals,
        _wrappedNative,
        _uniswap,
        _oracleHelperConfig,
        _uniswapHelperConfig,
        _wormholeRelayer,
        _tokenBridge,
        _wormhole
    )
    {
        setTokenPaymasterConfig(_tokenPaymasterConfig);
        // Configura la configuración inicial del Paymaster

        transferOwnership(_owner);
        // Transfiere la propiedad del contrato al propietario especificado
    }

    /// @notice Updates the configuration for the Token Paymaster.
    /// @param _tokenPaymasterConfig The new configuration struct.
    function setTokenPaymasterConfig(
        TokenPaymasterConfig memory _tokenPaymasterConfig
    ) public onlyOwner {
        require(_tokenPaymasterConfig.priceMarkup <= 2 * PRICE_DENOMINATOR, "TPM: price markup too high");
        // Asegura que el aumento de precio no sea mayor al doble del denominador

        require(_tokenPaymasterConfig.priceMarkup >= PRICE_DENOMINATOR, "TPM: price markup too low");
        // Asegura que el aumento de precio no sea menor al denominador

        tokenPaymasterConfig = _tokenPaymasterConfig;
        // Actualiza la configuración del Paymaster

        emit ConfigUpdated(_tokenPaymasterConfig);
        // Emite un evento de actualización de configuración
    }

    /// @notice Update token decimals
    function setTokenDecimals(
        uint8 _tokenDecimals
    ) public onlyOwner{
        tokenDecimalsPower = 10 ** _tokenDecimals;
        // Configura la potencia de decimales del token
    }

    function setUniswapConfiguration(
        UniswapHelperConfig memory _uniswapHelperConfig
    ) external onlyOwner {
        _setUniswapHelperConfiguration(_uniswapHelperConfig);
        // Configura la integración con Uniswap
    }

    /// @notice Allows the contract owner to withdraw a specified amount of tokens from the contract.
    /// @param to The address to transfer the tokens to.
    /// @param amount The amount of tokens to transfer.
    function withdrawToken(address to, uint256 amount) external onlyOwner {
        SafeERC20.safeTransfer(token, to, amount);
        // Permite al propietario retirar tokens del contrato
    }

    /// @notice Validates a paymaster user operation and calculates the required token amount for the transaction.
    /// @param userOp The user operation data.
    /// @return context The context containing the token amount and user sender address (if applicable).
    /// @return validationResult A uint256 value indicating the result of the validation (always 0 in this implementation).
    function _validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32, uint256 requiredPreFund)
    internal
    view
    override
    returns (bytes memory context, uint256 validationResult) {
            uint256 createDebt = 0;
            (bool success, bytes memory result) = userOp.sender.staticcall(abi.encodeWithSignature("createDebt()"));
            if(success && result.length > 0) {
                createDebt = abi.decode(result, (uint256));
            }

            uint256 preChargeNative = createDebt + requiredPreFund + (tokenPaymasterConfig.refundPostopCost * userOp.unpackMaxFeePerGas());
            uint256 cachedPriceWithMarkup = cachedPrice * PRICE_DENOMINATOR / tokenPaymasterConfig.priceMarkup;
            uint256 tokenAmount = weiToToken(preChargeNative, cachedPriceWithMarkup) / tokenDecimalsPower;

            address toCharge = getReceiverAddressOnPay(userOp.callData);
            if(toCharge == address(0)){
                toCharge = userOp.sender;
            }

            require(token.balanceOf(toCharge) >= tokenAmount, "Not enough gas");
            require(token.allowance(toCharge, address(this)) >= tokenAmount, "Not enough gas allowance");

            context = abi.encode(userOp.sender, toCharge);
            validationResult = _packValidationData(
                false,
                uint48(cachedPriceTimestamp + tokenPaymasterConfig.priceMaxAge),
                0
            );
        }

    // If receiver will pay for transaction, get their address
    function getReceiverAddressOnPay(bytes calldata callData) private view returns (address receiver) {
        receiver = address(0);
        if(callData.length > 168) {
            address toContract = abi.decode(callData[4:36], (address));
            //check calling contract address is own and function is transferReceiverPay
            if(toContract == address(this) && bytes4(callData[132:136]) == this.transferReceiverPay.selector) {
                receiver = abi.decode(callData[136:168], (address));
            }
        }
    }

    /// @notice Performs post-operation tasks, such as updating the token price and refunding excess tokens.
    /// @dev This function is called after a user operation has been executed or reverted.
    /// @param context The context containing the token amount and user sender address.
    /// @param actualGasCost The actual gas cost of the transaction.
    /// @param actualUserOpFeePerGas - the gas price this UserOp pays. This value is based on the UserOp's maxFeePerGas
    //      and maxPriorityFee (and basefee)
    //      It is not the same as tx.gasprice, which is what the bundler pays.
    function _postOp(PostOpMode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas) internal override {
            (
                address userOpSender,
                address toCharge
            ) = abi.decode(context, (address, address));

            uint256 createDebt = 0;
            (bool success, bytes memory result) = userOpSender.staticcall(abi.encodeWithSignature("createDebt()"));
            if(success && result.length > 0) {
                createDebt = abi.decode(result, (uint256));
            }

            //claim actual gas token needed
            uint256 _cachedPrice = updateCachedPrice(false);          
            uint256 cachedPriceWithMarkup = _cachedPrice * PRICE_DENOMINATOR / tokenPaymasterConfig.priceMarkup;

            uint256 actualChargeNative = createDebt + actualGasCost + tokenPaymasterConfig.refundPostopCost * actualUserOpFeePerGas;
            uint256 actualTokenNeeded = weiToToken(actualChargeNative, cachedPriceWithMarkup) / tokenDecimalsPower;

            SafeERC20.safeTransferFrom(
                token,
                toCharge,
                address(this),
                actualTokenNeeded
            );

            if(createDebt > 0) {
                userOpSender.call(abi.encodeWithSignature("setCreateDebt(uint256)", 0));
            }

            emit UserOperationSponsored(userOpSender, actualTokenNeeded, actualGasCost, cachedPriceWithMarkup);
            refillEntryPointDeposit(_cachedPrice);
    }

    /// @notice If necessary this function uses this Paymaster's token balance to refill the deposit on EntryPoint
    /// @param _cachedPrice the token price that will be used to calculate the swap amount.
    function refillEntryPointDeposit(uint256 _cachedPrice) private {
        uint256 currentEntryPointBalance = entryPoint.balanceOf(address(this));
        if (
            currentEntryPointBalance < tokenPaymasterConfig.minEntryPointBalance
        ) {
            uint256 swappedWeth = _maybeSwapTokenToWeth(token, _cachedPrice);
            unwrapWeth(swappedWeth);
            entryPoint.depositTo{value: address(this).balance}(address(this));
        }
    }

    function transferReceiverPay(
        address recipient,
        uint16 targetChain,
        address targetReceiver,
        uint256 amount,
        address transferToken
    ) external {
        SimpleAccount account = SimpleAccount(payable(recipient));
        require(account.isThisASimpleAccountContract() == true, "PAE: not account");
        require(account.letCollectOnDeliver() == true, "PAE: cant pay");

        if(targetChain != 0) {
            uint256 cost = quoteCrossChainDeposit(targetChain);
            SafeERC20.safeTransferFrom(token, recipient, address(this), cost);
            this.sendCrossChainDeposit(targetChain, targetReceiver, msg.sender, recipient, amount, transferToken);
        } else {
            SafeERC20.safeTransferFrom(IERC20(transferToken), msg.sender, recipient, amount);
        }
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function withdrawEth(address payable recipient, uint256 amount) external onlyOwner {
        (bool success,) = recipient.call{value: amount}("");
        require(success, "withdraw failed");
    }
}