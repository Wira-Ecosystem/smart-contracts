// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/interfaces/PackedUserOperation.sol";

// Simple mock for IEntryPoint to facilitate testing
contract MockEntryPoint is IEntryPoint {
    mapping(address => uint256) public balances;

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function depositTo(address account) external payable {
        balances[account] += msg.value;
    }

    function withdrawTo(address payable withdrawAddress, uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        withdrawAddress.transfer(amount);
    }

    // Stub other functions to satisfy interface
    function getUserOpHash(PackedUserOperation calldata) external pure returns (bytes32) {
        return keccak256("mock");
    }

    function handleOps(PackedUserOperation[] calldata, address payable) external {}
    function handleAggregatedOps(UserOpsPerAggregator[] calldata, address payable) external {}
    function simulateValidation(PackedUserOperation calldata) external {}
    function getNonce(address, uint192) external pure returns (uint256) { return 0; }
    function incrementNonce(uint192) external {}

    function addStake(uint32 _unstakeDelaySec) external payable {}
    function delegateAndRevert(address target, bytes calldata data) external {}
    function getDepositInfo(
        address account
    ) external view returns (DepositInfo memory info) {}
    function getSenderAddress(bytes memory initCode) external {}
    function unlockStake() external {}
    function withdrawStake(address payable withdrawAddress) external {}
}