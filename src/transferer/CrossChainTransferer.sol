// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@wormhole/src/WormholeRelayerSDK.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../utils/UniswapHelper.sol";
import "../utils/OracleHelper.sol";

contract CrossChainTransferer is UniswapHelper, OracleHelper, TokenSender, TokenReceiver {
    uint256 constant GAS_LIMIT = 250_000;

    modifier senderIsValid(address sender) {
        require(msg.sender == address(this) || msg.sender == sender, "Sender must be contract itself or msg.sender");
        _;
    }

    constructor(
        IERC20Metadata _token,
        uint8 _tokenDecimals,
        IERC20 _wrappedNative,
        ISwapRouter _uniswap,
        OracleHelperConfig memory _oracleHelperConfig,
        UniswapHelperConfig memory _uniswapHelperConfig,
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole
    )
    OracleHelper(
        _oracleHelperConfig,
        _tokenDecimals
    )
    UniswapHelper(
        _token,
        _wrappedNative,
        _uniswap,
        _uniswapHelperConfig
    )
    TokenBase(_wormholeRelayer, _tokenBridge, _wormhole) {}

    function quoteCrossChainDeposit(
        uint16 targetChain
    ) public view returns (uint256 cost) {
        uint256 deliveryCost;
        (deliveryCost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0,
            GAS_LIMIT
        );

        uint nativeTokenCost = deliveryCost + wormhole.messageFee();
        cost = weiToToken(nativeTokenCost, cachedPrice) / tokenDecimalsPower;
    }

    function sendCrossChainDeposit(
        uint16 targetChain,
        address sender,
        address recipient,
        uint256 amount,
        address transferToken
    ) external senderIsValid(sender) {
        if(msg.sender == sender) {
            SafeERC20.safeTransferFrom(token, msg.sender, address(this), quoteCrossChainDeposit(targetChain));
        }
        SafeERC20.safeTransferFrom(IERC20(transferToken), sender, address(this), amount);

        bytes memory payload = abi.encode(recipient);
        sendTokenWithPayloadToEvm(
            targetChain,
            address(this),
            payload,
            0,
            GAS_LIMIT,
            transferToken,
            amount
        );
    }

    // Function to receive the cross-chain payload and tokens with emitter validation
    function receivePayloadAndTokens(
        bytes memory payload,
        TokenReceived[] memory receivedTokens,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 // deliveryHash
    )
        internal
        override
        onlyWormholeRelayer
        isRegisteredSender(sourceChain, sourceAddress)
    {
        require(receivedTokens.length == 1, "Expected 1 token transfer");

        // Decode the recipient address from the payload
        address recipient = abi.decode(payload, (address));

        // Transfer the received tokens to the intended recipient
        SafeERC20.safeTransfer(IERC20(receivedTokens[0].tokenAddress), recipient, receivedTokens[0].amount);
    }
}