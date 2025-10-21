// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {TokenSender, TokenBase} from "@wormhole/src/WormholeRelayerSDK.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {UniswapHelper, ISwapRouter} from "../utils/UniswapHelper.sol";
import {OracleHelper} from "../utils/OracleHelper.sol";

contract CrossChainTransferer is UniswapHelper, OracleHelper, TokenSender {

    uint256 constant GAS_LIMIT = 250_000;

    event CrossChainSent(uint64 sequence);

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
        address targetReceiver,
        address sender,
        address recipient,
        uint256 amount,
        address transferToken
    ) external senderIsValid(sender) {
        if(msg.sender == sender) {
            SafeERC20.safeTransferFrom(TOKEN, msg.sender, address(this), quoteCrossChainDeposit(targetChain));
        }
        SafeERC20.safeTransferFrom(IERC20(transferToken), sender, address(this), amount);

        bytes memory payload = abi.encode(recipient);
        uint64 sequence = sendTokenWithPayloadToEvm(
            targetChain,
            targetReceiver,
            payload,
            0,
            GAS_LIMIT,
            transferToken,
            amount
        );

        emit CrossChainSent(sequence);
    }
}