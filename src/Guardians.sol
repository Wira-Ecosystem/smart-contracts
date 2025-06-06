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
        address newOwner; // nuevo propietario propuesto
        uint8 approvals; // votos acumulados
        bool executed; // si ya se ejecutó en SimpleAccount
    }

    struct GuardianInfo {
        Status state;
        uint40 invitedAt;
    }

    address public immutable owner; // address from SimpleAccount to delegate gaurdians
    uint8 public requiredApprovals = 1;

    mapping(bytes32 => GuardianInfo) public guardians;
    mapping(bytes32 => Recovery) public recoveries;
    mapping(bytes32 => mapping(bytes32 => bool)) public voted;

    event GuardianInvited(bytes32 indexed did);
    event GuardianAccepted(bytes32 indexed did);
    event GuardianRemoved(bytes32 indexed did);
    event QuorumChanged(uint8 newQuorum);
    event RecoveryProposed(address indexed newOwner);
    event RecoveryApproved(address indexed newOwner, bytes32 indexed guardian);
    event RecoveryExecuted(address indexed newOwner);

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
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
        g.state = Status.ACCEPTED;
        emit GuardianAccepted(guardianHash);
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
    function approveRecovery(bytes32 guardianHash, address newOwner) external {
        GuardianInfo storage gi = guardians[guardianHash];
        require(gi.state == Status.ACCEPTED, "guardian not accepted");

        bytes32 recKey = keccak256(abi.encode(newOwner));
        require(!voted[guardianHash][recKey], "already voted");

        Recovery storage r = recoveries[recKey];
        if (r.newOwner == address(0)) {
            r.newOwner = newOwner;
            emit RecoveryProposed(newOwner);
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
}
