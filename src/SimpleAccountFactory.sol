// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./SimpleAccount.sol";

/**
 * A sample factory contract for SimpleAccount
 * A UserOperations "initCode" holds the address of the factory, and a method call (to createAccount, in this sample factory).
 * The factory's createAccount returns the target account address even if it is already installed.
 * This way, the entryPoint.getSenderAddress() can be called either before or after the account is created.
 */
contract SimpleAccountFactory {
    SimpleAccount public immutable accountImplementation;

    mapping(uint256 => address) public routers;
    mapping(uint256 => address) public links;

    event AccountCreated(
        uint256 chainid,
        address router,
        address link,
        address account
    );

    constructor(IEntryPoint _entryPoint) {
        //Chainlink testnet routers
        //Polygon Amoy
        routers[80002] = 0x9C32fCB86BF0f4a1A8921a9Fe46de3198bb884B2;
        //Op sepolia
        routers[11155420] = 0x114A20A10b43D4115e5aeef7345a1A71d2a60C57;
        //Base Sepolia
        routers[84532] = 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;
        //Sepolia
        routers[11155111] = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

        //Chainlink testnet links
        //Polygon Amoy
        links[80002] = 0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904;
        //Op sepolia
        links[11155420] = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
        //Base Sepolia
        links[84532] = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
        //Sepolia
        links[11155111] = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

        address currentRouter = routers[block.chainid];
        address currentLink = links[block.chainid];
        accountImplementation = new SimpleAccount(_entryPoint, currentRouter, currentLink);

        emit AccountCreated(block.chainid, currentRouter, currentLink, address(accountImplementation));
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     */
    function createAccount(address owner,uint256 salt) public returns (SimpleAccount ret) {
        address addr = getAddress(owner, salt);
        uint256 codeSize = addr.code.length;
        if (codeSize > 0) {
            return SimpleAccount(payable(addr));
        }
        ret = SimpleAccount(payable(new ERC1967Proxy{salt : bytes32(salt)}(
                address(accountImplementation),
                abi.encodeCall(SimpleAccount.initialize, (owner))
            )));
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     */
    function getAddress(address owner,uint256 salt) public view returns (address) {
        return Create2.computeAddress(bytes32(salt), keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    address(accountImplementation),
                    abi.encodeCall(SimpleAccount.initialize, (owner))
                )
            )));
    }
}
