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
    IEntryPoint public immutable entryPoint;
    address public fcOwner;
    SimpleAccount public accountImplementation;
    mapping(address => address) public guardianOf;
    uint256 public gasToDebt = 0;

    event AccountCreated(
        uint256 chainid,
        address account
    );

    event GuardianCreated(address indexed account, address indexed guardian);

    modifier onlyOwner {
        require(msg.sender == fcOwner, "Only owner");
        _;
    }

    constructor(IEntryPoint _entryPoint, address _owner) {
        fcOwner = _owner;
        entryPoint = _entryPoint;
    }

    function initialize(address _tokenPaymaster) external onlyOwner {
        require(address(accountImplementation) == address(0), "Already initialized");
        accountImplementation = new SimpleAccount(entryPoint, _tokenPaymaster);
        emit AccountCreated(block.chainid, address(accountImplementation));
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     */
    function createAccount(address owner,uint256 salt) public returns (SimpleAccount ret) {
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
        
        ret.setCreateDebt(gasToDebt);
    }

    function createGuardianForAccount(
        address account,
        uint256 salt
    ) external returns (address) {
        require(account != address(0), "Invalid account");
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
    function getAddress(address owner,uint256 salt) public view returns (address) {
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
    ) public view returns (address) {
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

    function setGasToDebt(uint256 _gasToDebt) external onlyOwner {
        gasToDebt = _gasToDebt;
    }

    /**
     * Add stake for this factory.
     * This method can also carry eth value to add to the current stake.
     * @param unstakeDelaySec - The unstake delay for this factory. Can only be increased.
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
    }

    /**
     * Unlock the stake, in order to withdraw it.
     * The factory can't serve requests once unlocked, until it calls addStake again
     */
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    /**
     * Withdraw the entire factory's stake.
     * stake must be unlocked first (and then wait for the unstakeDelay to be over)
     * @param withdrawAddress - The address to send withdrawn value.
     */
    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
    }
}
