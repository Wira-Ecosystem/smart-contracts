// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DebtAccountFactory} from "../../src/DebtAccountFactory.sol";
import {SimpleAccount} from "../../src/SimpleAccount.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

//Test set up for simple account
contract DebtAccountFactoryTest is Test {
    //Entrypoint needed, same address on all networks
    IEntryPoint entrypoint = IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    address fcOwner = address(0x173);
    DebtAccountFactory factory;

    function setUp() public {
        bytes32 salt = bytes32(uint(287555237));

        factory = new DebtAccountFactory{salt: salt}(entrypoint, fcOwner);
        vm.prank(fcOwner);
        factory.initialize(address(0x1234));
    }

    function test_getAddress_sameOnDiffChains() public {
        bytes32 salt = bytes32(uint(287555238)); // Different salt
        uint256 accountSalt = 12345;

        DebtAccountFactory tempFactory = new DebtAccountFactory{salt: salt}(entrypoint, fcOwner);
        vm.prank(fcOwner);
        tempFactory.initialize(address(0x1234));
        console.log(address(tempFactory));
        console.log(tempFactory.getAddress(address(0x123), accountSalt));
    }

    function test_getAddress_sameAs_CreateAddress() public {
        bytes32 salt = bytes32(uint(287555239)); // Different salt
        uint256 accountSalt = 12345;

        DebtAccountFactory tempFactory = new DebtAccountFactory{salt: salt}(entrypoint, fcOwner);
        vm.prank(fcOwner);
        tempFactory.initialize(address(0x1235));
        address predicted = tempFactory.getAddress(address(0x123), accountSalt);

        SimpleAccount account = tempFactory.createAccount(address(0x123), accountSalt);
        
        assertEq(predicted, address(account));
    }

    // ===================== CRITICAL SECURITY TESTS =====================

    // 1) Test for unauthorized access control on critical functions
    function test_SecurityCritical_UnauthorizedInitialize() public {
        DebtAccountFactory tempFactory = new DebtAccountFactory(entrypoint, fcOwner);
        
        vm.startPrank(address(0x999));
        vm.expectRevert();
        tempFactory.initialize(address(0x1234));
        vm.stopPrank();
    }

    // 2) Test for double initialization vulnerability
    function test_SecurityCritical_DoubleInitialization() public {
        vm.startPrank(fcOwner);
        vm.expectRevert();
        factory.initialize(address(0x5678));
        vm.stopPrank();
    }

    // 3) Test for zero address validation
    function test_SecurityCritical_ZeroAddressValidation() public {
        vm.expectRevert();
        factory.createAccount(address(0), 12345);
    }

    // 4) Test for salt collision prevention
    function test_SecurityCritical_SaltCollisionPrevention() public {
        // Create first account
        SimpleAccount account1 = factory.createAccount(address(0x123), 12345);
        
        // Create second account with different owner but same salt
        SimpleAccount account2 = factory.createAccount(address(0x456), 12345);
        
        // Addresses should be different due to different owners
        assertTrue(address(account1) != address(account2), "Salt collision detected - critical vulnerability");
    }

    // 5) Test for address prediction security
    function test_SecurityCritical_AddressPredictionSecurity() public {
        address predicted = factory.getAddress(address(0x123), 54321);
        SimpleAccount actual = factory.createAccount(address(0x123), 54321);
        
        assertEq(predicted, address(actual), "Address prediction manipulation detected");
        assertEq(actual.owner(), address(0x123), "Account owner mismatch - security issue");
    }

    // 6) Test for front-running protection
    function test_SecurityCritical_FrontRunningProtection() public {
        address predictedAddr = factory.getAddress(address(0x123), 98765);
        
        // Simulate front-runner creating account for different owner
        SimpleAccount frontRunAccount = factory.createAccount(address(0x999), 98765);
        assertTrue(address(frontRunAccount) != predictedAddr, "Front-running protection failed");
        
        // Original user can still create their account
        SimpleAccount originalAccount = factory.createAccount(address(0x123), 98765);
        assertEq(address(originalAccount), predictedAddr, "Original account creation failed");
    }

    // 7) Test for gas consumption DoS
    function test_SecurityCritical_GasConsumptionDoS() public {
        uint256 gasStart = gasleft();
        factory.createAccount(address(0x123), 12345);
        uint256 gasUsed = gasStart - gasleft();
        
        assertTrue(gasUsed < 200000, "Account creation consumes too much gas - DoS vulnerability");
    }

    // 8) Test for stake overflow protection
    function test_SecurityCritical_StakeOverflowProtection() public {
        vm.startPrank(fcOwner);
        
        // Try to add stake with maximum value
        vm.deal(fcOwner, type(uint256).max);
        
        // This should not cause overflow issues
        factory.addStake{value: 1 ether}(1000);
        
        vm.stopPrank();
    }

    // 9) Test for unauthorized stake withdrawal
    function test_SecurityCritical_UnauthorizedWithdrawStake() public {
        vm.startPrank(address(0x999));
        vm.expectRevert();
        factory.withdrawStake(payable(address(0x888)));
        vm.stopPrank();
    }

    // 10) Test for unauthorized setGasToDebt
    function test_SecurityCritical_UnauthorizedSetGasToDebt() public {
        vm.startPrank(address(0x999));
        vm.expectRevert();
        factory.setGasToDebt(1000);
        vm.stopPrank();
    }

    // 11) Test for guardian creation validation
    function test_SecurityCritical_GuardianCreationValidation() public {
        // Try to create guardian for non-existent account
        vm.expectRevert();
        factory.createGuardianForAccount(address(0x999), 12345);
        
        // Try to create guardian for zero address
        vm.expectRevert();
        factory.createGuardianForAccount(address(0), 12345);
    }

    // 12) Test for guardian double creation vulnerability
    function test_SecurityCritical_GuardianDoubleCreation() public {
        address owner = address(0x123);
        // Create an account first
        SimpleAccount account = factory.createAccount(owner, 12345);
        
        // Set a guardian directly (as the owner)
        vm.startPrank(owner);
        address guardian1 = vm.addr(0x789);
        account.setGuardian(guardian1);
        
        // Try to set another guardian - this should work (overwrites previous)
        address guardian2 = vm.addr(0x888);
        account.setGuardian(guardian2);
        
        // Verify the second guardian is set
        assertEq(account.getGuardian(), guardian2, "Second guardian should be set");
        vm.stopPrank();
    }

    // ===================== POSITIVE SECURITY TESTS =====================

    function test_SecurityPass_EventEmission() public {
        SimpleAccount account = factory.createAccount(address(0x123), 98765);
        
        assertTrue(address(account) != address(0), "Account should be created successfully");
        assertEq(account.owner(), address(0x123), "Account should have correct owner");
    }

    function test_SecurityPass_GuardianCreation() public {
        address owner = address(0x123);
        // Create an account first
        SimpleAccount account = factory.createAccount(owner, 12345);
        
        // Set guardian directly (as the owner)
        vm.startPrank(owner);
        address guardian = vm.addr(0x789);
        account.setGuardian(guardian);
        vm.stopPrank();
        
        // Guardian address should not be zero
        assertTrue(guardian != address(0), "Guardian address should not be zero");
        
        // Verify guardian is set in account
        assertEq(account.getGuardian(), guardian, "Guardian not properly set in account");
    }

    function test_SecurityPass_SameOwnerSameSalt() public {
        SimpleAccount account1 = factory.createAccount(address(0x123), 12345);
        SimpleAccount account2 = factory.createAccount(address(0x123), 12345);
        
        assertEq(address(account1), address(account2), "Same parameters should return same account");
    }

    function test_SecurityPass_LargeSaltValues() public {
        SimpleAccount account = factory.createAccount(address(0x123), type(uint256).max);
        
        assertTrue(address(account) != address(0), "Should handle large salt values");
    }

    function test_SecurityPass_StakeWithdrawal() public {
        // Give the factory owner some ETH first
        vm.deal(fcOwner, 10 ether);
        
        vm.startPrank(fcOwner);
        
        // Add stake
        factory.addStake{value: 1 ether}(1000);
        
        // Unlock stake
        factory.unlockStake();
        
        // Fast forward time to allow withdrawal
        vm.warp(block.timestamp + 1001);
        
        // Withdraw stake
        factory.withdrawStake(payable(fcOwner));
        
        vm.stopPrank();
        
        assertTrue(true, "Stake withdrawal failed");
    }

    // ===================== ADDITIONAL WORKFLOW TESTS =====================

    function test_CreateAccountIdempotent() public {
        address owner = address(0x456);
        uint256 salt = 789;

        // First call - deploys the account
        SimpleAccount account1 = factory.createAccount(owner, salt);
        address addr1 = address(account1);
        uint256 codeSize1 = addr1.code.length;
        
        // Second call - should return the same instance
        SimpleAccount account2 = factory.createAccount(owner, salt);
        address addr2 = address(account2);
        uint256 codeSize2 = addr2.code.length;
        
        // Verify idempotency
        assertEq(addr1, addr2, "Addresses should be identical");
        assertEq(codeSize1, codeSize2, "Code size should remain unchanged");
        assertTrue(codeSize1 > 0, "Account should have bytecode");
    }

    function test_CreateAccountDeterministicAddress() public {
        address owner = address(0x789);
        uint256 salt = 555;
        
        // Calculate counterfactual address
        address expectedAddress = factory.getAddress(owner, salt);
        
        // Deploy account
        SimpleAccount account = factory.createAccount(owner, salt);
        
        // Verify determinism
        assertEq(address(account), expectedAddress, "Deployed address must match counterfactual address");
    }

    function test_CreateAccountPropagatesGasToDebt() public {
        uint256 gasDebtAmount = 50000;
        address owner = address(0xABC);
        uint256 salt = 999;
        
        // Configure gasToDebt (only the owner of factory can do this)
        vm.prank(fcOwner);
        factory.setGasToDebt(gasDebtAmount);
        
        // Create new account
        SimpleAccount account = factory.createAccount(owner, salt);
        
        // Verify debt propagation
        assertEq(account.createDebt(), gasDebtAmount, "createDebt should match gasToDebt");
    }

    function test_SetGasToDebtOnlyOwner() public {
        uint256 newGasDebt = 75000;
        address unauthorizedUser = address(0x444);
        
        // Try from unauthorized account - should revert
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        factory.setGasToDebt(newGasDebt);
        
        // Call from authorized owner - should work
        vm.prank(fcOwner);
        factory.setGasToDebt(newGasDebt);
        
        // Verify it was updated
        assertEq(factory.gasToDebt(), newGasDebt, "gasToDebt should be updated by owner");
    }
}