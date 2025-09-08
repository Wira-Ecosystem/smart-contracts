// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "./SimpleAccount.sol";
import "./Guardians.sol";
/**
 * A sample factory contract for SimpleAccount
 * A UserOperations "initCode" holds the address of the factory, and a method call (to createAccount, in this sample factory).
 * The factory's createAccount returns the target account address even if it is already installed.
 * This way, the entryPoint.getSenderAddress() can be called either before or after the account is created.
 */
contract SimpleAccountFactory is Ownable {
    SimpleAccount public accountImplementation;
    mapping(address => address) public guardianOf;

    event AccountCreated(
        uint256 chainid,
        address account
    );

    event GuardianCreated(address indexed account, address indexed guardian);

    modifier nonZeroAddress(address addr) {
        require(addr != address(0), "Zero address no allowed");
        _;
    }

    constructor(IEntryPoint _entryPoint, address initOwner) Ownable(initOwner) {
        accountImplementation = new SimpleAccount(_entryPoint, address(0x0));
        emit AccountCreated(block.chainid, address(accountImplementation));
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     */
    function createAccount(address owner,uint256 salt) public nonZeroAddress(owner) returns (SimpleAccount ret) {
        require(owner != address(0), "Owner cannot be zero address");
        address addr = getAddress(owner, salt);
        uint256 codeSize = addr.code.length;
        if (codeSize > 0) {
            return SimpleAccount(payable(addr));
        }
        ret = SimpleAccount(payable(new ERC1967Proxy{salt : bytes32(salt)}(
                address(accountImplementation),
                abi.encodeCall(SimpleAccount.initialize, (owner, address(this)))
            )));
    }

    function createGuardianForAccount(
        address account,
        uint256 salt
    ) external nonZeroAddress(account) returns (address) {
        require(guardianOf[account] == address(0), "Guardian already exists");

        require(
            SimpleAccount(payable(account)).isThisASimpleAccountContract(),
            "Not a SimpleAccount"
        );

        bytes32 guardianSalt = keccak256(abi.encodePacked(account, salt));
        Guardian guardianContract = new Guardian{salt: guardianSalt}(account);

        SimpleAccount(payable(account)).setGuardian(address(guardianContract));

        guardianOf[account] = address(guardianContract);
        emit GuardianCreated(account, address(guardianContract));

        return address(guardianContract);
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     */
    function getAddress(address owner,uint256 salt) public view nonZeroAddress(owner) returns (address) {
        return Create2.computeAddress(bytes32(salt), keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    address(accountImplementation),
                    abi.encodeCall(SimpleAccount.initialize, (owner, address(this)))
                )
            )
        ));
    }

    function getGuardianAddress(
        address account,
        uint256 salt
    ) public view nonZeroAddress(account) returns (address) {
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
    }

    function setAccountImplementation(address payable newImpl) external onlyOwner {
        accountImplementation = SimpleAccount(newImpl);
    }
}
