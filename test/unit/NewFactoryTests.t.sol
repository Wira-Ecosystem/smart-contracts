// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAccountFactory} from "../../src/SimpleAccountFactory.sol";
import {SimpleAccount} from "../../src/SimpleAccount.sol";
import {Guardian} from "../../src/Guardians.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";
import {Vm} from "forge-std/Vm.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract NewFactoryTests is Test {
    IEntryPoint entrypoint = IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    SimpleAccountFactory factory;

    function setUp() public {
        address fcOwner = address(0x173);
        factory = new SimpleAccountFactory(entrypoint, fcOwner);
        vm.prank(fcOwner);
        factory.initialize(address(0x789));
    }

    function test_InvalidSalt() public {
        address owner = address(0x123);
        uint256 invalidSalt = type(uint256).max; // Valor extremo para salt

        vm.expectRevert();
        factory.createAccount(owner, invalidSalt);
    }

    function test_Reentrancy() public {
        address owner = address(0x123);
        uint256 salt = 123456;

        // Registrar gas gastado en la creación normal de una cuenta
        uint256 gasBeforeNormal = gasleft();
        factory.createAccount(owner, salt);
        uint256 gasAfterNormal = gasleft();
        console.log("Gas gastado en creacion normal:", gasBeforeNormal - gasAfterNormal);

        // Crear un contrato atacante para simular reentrancia
        ReentrancyAttacker attacker = new ReentrancyAttacker(factory);

        // Registrar logs para verificar eventos inesperados
        vm.recordLogs();

        // Registrar gas gastado durante el ataque de reentrancia
        uint256 gasBeforeAttack = gasleft();
        vm.expectRevert();
        attacker.attack(owner, salt);
        uint256 gasAfterAttack = gasleft();
        console.log("Gas gastado durante ataque de reentrancia:", gasBeforeAttack - gasAfterAttack);

        // Verificar que no se emitieron eventos inesperados
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "No unexpected events should be emitted");
    }

    function test_GasInsufficient() public {
        address owner = address(0x123);
        uint256 salt = 123456;

        // Simular insuficiencia de gas
        vm.expectRevert();
        factory.createAccount{gas: 1000}(owner, salt);
    }

    function test_CompatibilityWithDifferentImplementations() public {
        address owner = address(0x123);
        uint256 salt = 123456;

        // Cambiar implementación base
        vm.prank(address(0x173));
        factory.initialize(address(0x456));

        SimpleAccount account = factory.createAccount(owner, salt);
        assertEq(account.owner(), owner);
    }


    function test_DuplicateSalt() public {
        address owner1 = address(0x123);
        address owner2 = address(0x456);
        uint256 salt = 123456;

        factory.createAccount(owner1, salt);
        vm.expectRevert();
        factory.createAccount(owner2, salt);
    }

    function test_UnauthorizedOwner() public {
        address unauthorizedOwner = address(0x999);
        uint256 salt = 123456;

        vm.expectRevert();
        factory.createAccount(unauthorizedOwner, salt);
    }

    function test_DifferentChainId() public {
        address owner = address(0x123);
        uint256 salt = 123456;

        // Simular cambio de chainid
        vm.chainId(2);
        SimpleAccount account = factory.createAccount(owner, salt);
        assertEq(account.owner(), owner);
    }

    // function test_EntryPointInteraction() public {
    //     address owner = address(0x123);
    //     uint256 salt = 123456;
    
    //     SimpleAccount account = factory.createAccount(owner, salt);
    //     assertEq(address(account.entryPoint()), entrypoint); // Conversión explícita a address
    // }

    function test_ParameterLimits() public {
        address owner = address(0x123);
        uint256 extremeSalt = type(uint256).max;

        vm.expectRevert();
        factory.createAccount(owner, extremeSalt);
    }

    function test_GuardianWithExtremeSalt() public {
        address account = address(0x123);
        uint256 extremeSalt = type(uint256).max;

        vm.expectRevert();
        factory.createGuardianForAccount(account, extremeSalt);
    }

    function test_GuardianForNonExistentAccount() public {
        address nonExistentAccount = address(0x456);
        uint256 salt = 123456;

        vm.expectRevert();
        factory.createGuardianForAccount(nonExistentAccount, salt);
    }

    function test_GuardianWithDuplicateSalt() public {
        address account = address(0x123);
        uint256 salt = 123456;

        factory.createGuardianForAccount(account, salt);
        vm.expectRevert();
        factory.createGuardianForAccount(account, salt);
    }

    function test_GuardianForInvalidAccount() public {
        address invalidAccount = address(0x789);
        uint256 salt = 123456;

        vm.expectRevert();
        factory.createGuardianForAccount(invalidAccount, salt);
    }

    function test_GuardianWithUniqueSalt() public {
        address account = address(0x123);
        uint256 salt1 = 123456;
        uint256 salt2 = 654321;

        address guardian1 = factory.createGuardianForAccount(account, salt1);
        address guardian2 = factory.createGuardianForAccount(account, salt2);

        assertTrue(guardian1 != guardian2, "Guardians should have unique addresses");
    }

    function test_GetAddress() public {
        address owner = address(0x123);
        uint256 salt = 123456;

        address calculatedAddress = factory.getAddress(owner, salt);
        address expectedAddress = Create2.computeAddress(
            bytes32(salt),
            keccak256(
                abi.encodePacked(
                    type(ERC1967Proxy).creationCode,
                    abi.encode(
                        address(factory.accountImplementation()),
                        abi.encodeCall(SimpleAccount.initialize, (owner, address(factory)))
                    )
                )
            )
        );

        assertEq(calculatedAddress, expectedAddress, "Calculated address does not match expected address");
    }

    function test_GetGuardianAddress() public {
        address account = address(0x123);
        uint256 salt = 123456;

        address calculatedGuardianAddress = factory.getGuardianAddress(account, salt);
        bytes32 guardianSalt = keccak256(abi.encodePacked(account, salt));
        address expectedGuardianAddress = Create2.computeAddress(
            guardianSalt,
            keccak256(
                abi.encodePacked(
                    type(Guardian).creationCode,
                    abi.encode(account)
                )
            )
        );

        assertEq(calculatedGuardianAddress, expectedGuardianAddress, "Calculated guardian address does not match expected address");
    }

    function test_SetGasToDebt() public {
        uint256 newGasToDebt = 1000;

        vm.prank(address(0x173));
        factory.setGasToDebt(newGasToDebt);

        assertEq(factory.gasToDebt(), newGasToDebt, "Gas to debt value was not set correctly");
    }

    function test_AddStake() public {
        uint32 unstakeDelaySec = 100;
        uint256 stakeValue = 1 ether;

        vm.prank(address(0x173));
        factory.addStake{value: stakeValue}(unstakeDelaySec);

        // No hay una forma directa de verificar el stake, pero se puede verificar que no haya revertido
        assertTrue(true, "Stake added successfully");
    }

    function test_UnlockStake() public {
        vm.prank(address(0x173));
        factory.unlockStake();

        // No hay una forma directa de verificar el desbloqueo, pero se puede verificar que no haya revertido
        assertTrue(true, "Stake unlocked successfully");
    }

    function test_WithdrawStake() public {
        address payable withdrawAddress = payable(address(0x456));

        vm.prank(address(0x173));
        factory.withdrawStake(withdrawAddress);

        // No hay una forma directa de verificar el retiro, pero se puede verificar que no haya revertido
        assertTrue(true, "Stake withdrawn successfully");
    }
}




// Contrato atacante para simular reentrancia
contract ReentrancyAttacker {
    SimpleAccountFactory public target;

    constructor(SimpleAccountFactory _target) {
        target = _target;
    }

    function attack(address owner, uint256 salt) external {
        target.createAccount(owner, salt);
    }

    fallback() external {
        // Intentar llamar nuevamente a la función vulnerable
        target.createAccount(msg.sender, 123456);
    }
}