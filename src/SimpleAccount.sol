// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@account-abstraction/core/BaseAccount.sol";
import "@account-abstraction/core/Helpers.sol";
import "./TokenCallbackHandler.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Guardians.sol";
/**
  * minimal account.
  *  this is sample minimal account.
  *  has execute, eth handling methods
  *  has a single signer that can send requests through the entryPoint.
  */
contract SimpleAccount is BaseAccount, TokenCallbackHandler, UUPSUpgradeable, Initializable {
    address public owner;
    IEntryPoint private immutable _entryPoint;
    address public guardian;
    address public factory;
    address public immutable tokenPaymaster;

    using SafeERC20 for IERC20;
    mapping(bytes32 => string) private _streamOf;

    error GuardianNotConfigurado();

    bool public immutable isThisASimpleAccountContract = true;
    bool public letCollectOnDeliver;
    uint256 public createDebt;

    event SimpleAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event OwnerRecovered(address indexed newOwner);
    event StreamRegistered(bytes32 indexed idHash, string streamId);

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    modifier onlyFactoryOrPaymaster() {
        require(msg.sender == tokenPaymaster || msg.sender == factory, "Only factory or paymaster");
        _;
    }

    modifier onlyGuardianContract() {
        require(msg.sender == address(guardian), "Only guardian contract can call");
        _;
    }

    function registerStream(
        bytes32 idHash,
        string calldata streamId
    ) external onlyOwner {
        require(bytes(_streamOf[idHash]).length == 0, "already registered");
        _streamOf[idHash] = streamId;
        emit StreamRegistered(idHash, streamId);
    }

    function getStream(bytes32 idHash) external view returns (string memory) {
        return _streamOf[idHash];
    }

     function setGuardian(address _guardian) external {
        require(_guardian != address(0), "Guardian cannot be zero address");
        guardian = _guardian;
    }

    function getGuardian() external view returns (address) {
        return guardian;
    }

    function executeRecovery(address newOwner) external {
        if (guardian == address(0)) revert GuardianNotConfigurado();
 
        require(msg.sender == guardian, "Only guardian can recover");
        require(newOwner != address(0), "New owner cannot be zero");

        owner = newOwner;
        emit OwnerRecovered(newOwner);
    }

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    constructor(IEntryPoint anEntryPoint, address _tokenPaymaster) {
        _entryPoint = anEntryPoint;
        tokenPaymaster = _tokenPaymaster;
        _disableInitializers();
    }

    function _onlyOwner() internal view {
        //directly from EOA owner, or through the account itself (which gets redirected through execute())
        require(msg.sender == owner || msg.sender == address(this), "only owner");
    }

    /**
     * execute a transaction (called directly from owner, or by entryPoint)
     * @param dest destination address to call
     * @param value the value to pass in this call
     * @param func the calldata to pass in this call
     */
    function execute(address dest, uint256 value, bytes calldata func) external {
        _requireFromEntryPointOrOwner();
        _call(dest, value, func);
    }

    /**
     * execute a sequence of transactions
     * @dev to reduce gas consumption for trivial case (no value), use a zero-length array to mean zero value
     * @param dest an array of destination addresses
     * @param value an array of values to pass to each call. can be zero-length for no-value calls
     * @param func an array of calldata to pass to each call
     */
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) external {
        _requireFromEntryPointOrOwner();
        require(dest.length == func.length && (value.length == 0 || value.length == func.length), "wrong array lengths");
        if (value.length == 0) {
            for (uint256 i = 0; i < dest.length; i++) {
                _call(dest[i], 0, func[i]);
            }
        } else {
            for (uint256 i = 0; i < dest.length; i++) {
                _call(dest[i], value[i], func[i]);
            }
        }
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of SimpleAccount must be deployed with the new EntryPoint address, then upgrading
      * the implementation by calling `upgradeTo()`
      * @param anOwner the owner (signer) of this account
     */
    function initialize(address anOwner, address itsFactory) public virtual initializer {
        _initialize(anOwner, itsFactory);
        emit SimpleAccountInitialized(_entryPoint, owner);
    }

    function _initialize(address anOwner, address itsFactory) internal virtual {
        owner = anOwner;
        factory = itsFactory;
        emit SimpleAccountInitialized(_entryPoint, owner);
    }

    // Require the function call went through EntryPoint or owner
    function _requireFromEntryPointOrOwner() internal view {
        require(msg.sender == address(entryPoint()) || msg.sender == owner, "account: not Owner or EntryPoint");
    }

    /// implement template method of BaseAccount
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
    internal override virtual returns (uint256 validationData) {
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        if (owner != ECDSA.recover(hash, userOp.signature))
            return SIG_VALIDATION_FAILED;
        return SIG_VALIDATION_SUCCESS;
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * check current account deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * deposit more funds for this account in the entryPoint
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value: msg.value}(address(this));
    }

    /**
     * withdraw value from the account's deposit
     * @param withdrawAddress target to send to
     * @param amount to withdraw
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyOwner {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        _onlyOwner();
    }

    /// @notice Fallback function to allow the contract to receive Ether.
    /// @dev This function has no function body, making it a default function for receiving Ether.
    /// It is automatically called when Ether is transferred to the contract without any data.
    receive() external payable {}

    /// @notice active/disable option to pay gas of receiving transfers
    function setCollectOnDeliver(bool _collectOnDeliver) external onlyOwner {
        letCollectOnDeliver = _collectOnDeliver;
    }

    /// @notice check create debt to paid (only paymaster or factory)
    function setCreateDebt(uint256 debt) external onlyFactoryOrPaymaster {
        createDebt = debt;
    }
}
