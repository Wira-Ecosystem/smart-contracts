// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./SimpleAccount.sol";
import "./Guardians.sol";
/**
 * A sample factory contract for SimpleAccount
 * A UserOperations "initCode" holds the address of the factory, and a method call (to createAccount, in this sample factory).
 * The factory's createAccount returns the target account address even if it is already installed.
 * This way, the entryPoint.getSenderAddress() can be called either before or after the account is created.
 */
contract SimpleAccountFactory {
    SimpleAccount public accountImplementation;
    mapping(address => address) public guardianOf;

    event AccountCreated(
        uint256 chainid,
        address account
    );

    event GuardianCreated(address indexed account, address indexed guardian);

    constructor() {}

    function initialize(IEntryPoint _entryPoint, address _tokenPaymaster) external {
        accountImplementation = new SimpleAccount(_entryPoint, _tokenPaymaster);
        emit AccountCreated(block.chainid, address(accountImplementation));
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     */
    function createAccount(address owner,uint256 salt) public returns (SimpleAccount ret) {
        uint256 gasToDebt = gasleft() + 6000000000;
        address addr = getAddress(owner, salt);
        uint256 codeSize = addr.code.length;
        if (codeSize > 0) {
            return SimpleAccount(payable(addr));
        }
        ret = SimpleAccount(payable(new ERC1967Proxy{salt : bytes32(salt)}(
                address(accountImplementation),
                abi.encodeCall(SimpleAccount.initialize, (owner, address(this)))
            )));
        
        ret.setCreateDebt(gasToDebt);

        // 2) Despliega el contrato Guardian para esta cuenta
        Guardian guardianContract = new Guardian(address(ret));

        // 3) Llamada setGuardian en la cuenta recién creada
        //ret.setGuardian(address(guardianContract));

        // 4) Guarda en el mapping y emite evento
        guardianOf[address(ret)] = address(guardianContract);
        emit GuardianCreated(address(ret), address(guardianContract));    
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
            )));
    }
}
