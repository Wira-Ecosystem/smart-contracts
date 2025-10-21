// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {TokenReceiver, TokenBase} from "@wormhole/src/WormholeRelayerSDK.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CrossChainReceiver is TokenReceiver {
    event TokenDelivered(address tokenAddress);
    event Received(address indexed sender, uint256 value);

    constructor(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole
    ) TokenBase(_wormholeRelayer, _tokenBridge, _wormhole) {}

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
        emit TokenDelivered(receivedTokens[0].tokenAddress);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}