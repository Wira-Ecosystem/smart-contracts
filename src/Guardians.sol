// SPDX-License-Identifier:  GPL-3.0
pragma solidity ^0.8.24;
interface ISimpleAccount {
    function executeRecovery(address newOwner) external;
}

contract Guardian {
    enum Status {
        NONE,
        PENDING,
        ACCEPTED,
        REJECTED
    }

    struct Recovery {
        address newOwner;
        uint8 approvals;
        bool executed;
        uint256 proposedAt;
    }



    struct GuardianInfo {
        Status state;
        uint40 invitedAt;
    }

    address public immutable owner; // address from SimpleAccount to delegate gaurdians
    uint8 public requiredApprovals = 1;
    uint256 public constant RECOVERY_PERIOD = 3 days;

    mapping(bytes32 => GuardianInfo) public guardians;
    mapping(bytes32 => Recovery) public recoveries;
    mapping(bytes32 => mapping(bytes32 => bool)) public voted;

    mapping(address => bytes32) public guardianAddressToHash;

    event GuardianInvited(bytes32 indexed did);
    event GuardianAccepted(
        bytes32 indexed did,
        address indexed guardianAddress
    );
    event GuardianRemoved(bytes32 indexed did);
    event QuorumChanged(uint8 newQuorum);
    event RecoveryProposed(address indexed newOwner, uint256 deadline);
    event RecoveryApproved(address indexed newOwner, bytes32 indexed guardian);
    event RecoveryExecuted(address indexed newOwner);

    error NotAuthorized();
    error InvalidGuardian();
    error RecoveryExpired();
    error AlreadyVoted();
    error GuardianNotAccepted();

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    modifier onlyActiveGuardian() {
        bytes32 guardianHash = guardianAddressToHash[msg.sender];
        if (guardianHash == bytes32(0)) revert InvalidGuardian();
        if (guardians[guardianHash].state != Status.ACCEPTED)
            revert GuardianNotAccepted();
        _;
    }

    function invite(bytes32 guardianHash) external onlyOwner {
        require(guardianHash != bytes32(0), "zero");
        GuardianInfo storage g = guardians[guardianHash];
        require(g.state == Status.NONE, "exists");
        g.state = Status.PENDING;
        g.invitedAt = uint40(block.timestamp);
        emit GuardianInvited(guardianHash);
    }

    function accept(bytes32 guardianHash) external {
        GuardianInfo storage g = guardians[guardianHash];
        require(g.state == Status.PENDING, "not pending");

        bytes32 expectedHash = keccak256(abi.encodePacked(msg.sender));
        require(guardianHash == expectedHash, "Invalid guardian hash");

        g.state = Status.ACCEPTED;
        guardianAddressToHash[msg.sender] = guardianHash;
        emit GuardianAccepted(guardianHash, msg.sender);
    }

    function remove(bytes32 guardianHash) external onlyOwner {
        delete guardians[guardianHash];
        emit GuardianRemoved(guardianHash);
    }

    function setQuorum(uint8 q) external onlyOwner {
        require(q > 0, "zero");
        requiredApprovals = q;
        emit QuorumChanged(q);
    }

    function isGuardian(bytes32 h) external view returns (bool) {
        return guardians[h].state == Status.ACCEPTED;
    }
    function approveRecovery(address newOwner) external onlyActiveGuardian {
        require(newOwner != address(0), "Invalid new owner");

        bytes32 guardianHash = guardianAddressToHash[msg.sender];
        bytes32 recKey = keccak256(abi.encode(newOwner));

        if (voted[guardianHash][recKey]) revert AlreadyVoted();

        Recovery storage r = recoveries[recKey];

        if (r.newOwner == address(0)) {
            r.newOwner = newOwner;
            r.proposedAt = block.timestamp;
            emit RecoveryProposed(newOwner, block.timestamp + RECOVERY_PERIOD);
        }

        if (block.timestamp > r.proposedAt + RECOVERY_PERIOD) {
            revert RecoveryExpired();
        }

        voted[guardianHash][recKey] = true;
        r.approvals += 1;
        emit RecoveryApproved(newOwner, guardianHash);


        if (!r.executed && r.approvals >= requiredApprovals) {
            r.executed = true;
            ISimpleAccount(owner).executeRecovery(newOwner);
            emit RecoveryExecuted(newOwner);
        }
    }

    function getRecoveryStatus(
        address newOwner
    )
        external
        view
        returns (uint8 approvals, bool executed, uint256 deadline, bool expired)
    {
        bytes32 recKey = keccak256(abi.encode(newOwner));
        Recovery storage r = recoveries[recKey];

        return (
            r.approvals,



            
            r.executed,
            r.proposedAt + RECOVERY_PERIOD,
            block.timestamp > r.proposedAt + RECOVERY_PERIOD
        );
    }

    function getGuardianByAddress(
        address guardianAddr
    ) external view returns (bytes32) {
        return guardianAddressToHash[guardianAddr];
    }
}
