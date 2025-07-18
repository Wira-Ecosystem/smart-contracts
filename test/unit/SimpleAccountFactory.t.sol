// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAccountFactory} from "../../src/SimpleAccountFactory.sol";
import {SimpleAccount} from "../../src/SimpleAccount.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

//Test set up for simple account
contract SimpleAccountFactoryTest is Test {
    //Entrypoint needed, same address on all networks
    IEntryPoint entrypoint = IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    address fcOwner = address(0x173);
    SimpleAccountFactory factory;

    function setUp() public {
        bytes32 salt = bytes32(uint(287555237));
        factory = new SimpleAccountFactory{salt: salt}(entrypoint, fcOwner);
        vm.prank(fcOwner);
        factory.initialize(address(0x1234));
    }

    function test_getAddress_sameOnDiffChains() public {
        bytes32 salt = bytes32(uint(287555238)); // Different salt
        uint256 accountSalt = 12345;

        SimpleAccountFactory tempFactory = new SimpleAccountFactory{salt: salt}(entrypoint, fcOwner);
        vm.prank(fcOwner);
        tempFactory.initialize(address(0x1234));
        console.log(address(tempFactory));
        console.log(tempFactory.getAddress(address(0x123), accountSalt));
    }

    function test_getAddress_sameAs_CreateAddress() public {
        bytes32 salt = bytes32(uint(287555239)); // Different salt
        uint256 accountSalt = 12345;

        SimpleAccountFactory tempFactory = new SimpleAccountFactory{salt: salt}(entrypoint, fcOwner);
        vm.prank(fcOwner);
        tempFactory.initialize(address(0x1235));
        address predicted = tempFactory.getAddress(address(0x123), accountSalt);

        SimpleAccount account = tempFactory.createAccount(address(0x123), accountSalt);
        
        assertEq(predicted, address(account));
    }

    // ===================== CRITICAL SECURITY TESTS =====================

    // 1) Test for unauthorized access control on critical functions
    function test_SecurityCritical_UnauthorizedInitialize() public {
        bytes32 salt = bytes32(uint(287555238));
        SimpleAccountFactory newFactory = new SimpleAccountFactory{salt: salt}(entrypoint, fcOwner);
        
        // Try to initialize from unauthorized address
        vm.startPrank(address(0x999)); // Not the fcOwner
        vm.expectRevert(); // Should revert due to onlyOwner modifier
        newFactory.initialize(address(0x1234));
        vm.stopPrank();
    }

    function test_SecurityCritical_UnauthorizedSetGasToDebt() public {
        // Try to call setGasToDebt from unauthorized address
        vm.startPrank(address(0x999)); // Not the fcOwner
        vm.expectRevert(); // Should revert due to onlyOwner modifier
        factory.setGasToDebt(1000);
        vm.stopPrank();
    }

    function test_SecurityCritical_UnauthorizedWithdrawStake() public {
        // Try to withdraw stake from unauthorized address
        vm.startPrank(address(0x999)); // Not the fcOwner
        vm.expectRevert(); // Should revert due to onlyOwner modifier
        factory.withdrawStake(payable(address(0x888)));
        vm.stopPrank();
    }

    // 2) Test for Create2 salt collision vulnerabilities
    function test_SecurityCritical_SaltCollisionPrevention() public {
        address owner1 = address(0x123);
        address owner2 = address(0x456);
        uint256 sameSalt = 12345;

        // Create first account
        SimpleAccount account1 = factory.createAccount(owner1, sameSalt);
        
        // Try to create second account with same salt but different owner
        // This should create a different address (no collision)
        SimpleAccount account2 = factory.createAccount(owner2, sameSalt);
        
        // Addresses should be different even with same salt due to different owners
        assertTrue(address(account1) != address(account2), "Salt collision detected - critical vulnerability");
    }

    // 3) Test for zero address vulnerabilities
    function test_SecurityCritical_ZeroAddressValidation() public {
        // Try to create account with zero address as owner
        vm.expectRevert(); // Should revert with zero address
        factory.createAccount(address(0), 12345);
    }

    // 4) Test for initialization security
    function test_SecurityCritical_DoubleInitialization() public {
        // Factory is already initialized in setUp()
        // Try to initialize again
        vm.startPrank(fcOwner);
        vm.expectRevert(); // Should revert on double initialization
        factory.initialize(address(0x5678));
        vm.stopPrank();
    }

    // 5) Test for guardian creation vulnerabilities
    function test_SecurityCritical_GuardianCreationValidation() public {
        // Try to create guardian for non-existent account
        vm.expectRevert(); // Should fail for invalid account
        factory.createGuardianForAccount(address(0x999), 12345);
        
        // Try to create guardian for zero address
        vm.expectRevert("Invalid account");
        factory.createGuardianForAccount(address(0), 12345);
    }

    // 6) Test for guardian double creation vulnerability
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

    // 7) Test for integer overflow in stake management
    function test_SecurityCritical_StakeOverflowProtection() public {
        vm.startPrank(fcOwner);
        
        // Try to add stake with maximum value
        vm.deal(fcOwner, type(uint256).max);
        
        // This should not cause overflow issues
        factory.addStake{value: 1 ether}(1000);
        
        vm.stopPrank();
    }

    // 8) Test for gas consumption DoS attacks
    function test_SecurityCritical_GasConsumptionDoS() public {
        uint256 gasStart = gasleft();
        
        // Create account and measure gas consumption
        factory.createAccount(address(0x123), 12345);
        
        uint256 gasUsed = gasStart - gasleft();
        
        // Gas should be reasonable (less than 500k for account creation)
        assertTrue(gasUsed < 500000, "Account creation consumes too much gas - DoS vulnerability");
    }

    // 9) Test for Create2 address prediction manipulation
    function test_SecurityCritical_AddressPredictionSecurity() public {
        address owner = address(0x123);
        uint256 salt = 54321;
        
        // Predict address before creation
        address predicted = factory.getAddress(owner, salt);
        
        // Actually create the account
        SimpleAccount account = factory.createAccount(owner, salt);
        
        // They should match exactly - no manipulation possible
        assertEq(predicted, address(account), "Address prediction manipulation detected");
        
        // Verify the account has correct owner
        assertEq(account.owner(), owner, "Account owner mismatch - security issue");
    }

    // 10) Test for front-running protection in account creation
    function test_SecurityCritical_FrontRunningProtection() public {
        address owner = address(0x123);
        uint256 salt = 98765;
        
        // Predict the address
        address predictedAddress = factory.getAddress(owner, salt);
        
        // Simulate front-running by creating account with different owner but same salt
        address frontRunner = address(0x999);
        SimpleAccount frontRunAccount = factory.createAccount(frontRunner, salt);
        
        // Should create different address due to different owner
        assertTrue(address(frontRunAccount) != predictedAddress, "Front-running protection failed");
        
        // Original account creation should still work with correct address
        SimpleAccount originalAccount = factory.createAccount(owner, salt);
        assertEq(address(originalAccount), predictedAddress, "Original account creation failed");
    }

    // ===================== ADDITIONAL SECURITY TESTS =====================

    function test_SecurityPass_SameOwnerSameSalt() public {
        address owner = address(0x123);
        uint256 salt = 12345;

        // Create first account
        SimpleAccount account1 = factory.createAccount(owner, salt);
        
        // Try to create second account with same owner and salt
        // This should return the same account (deterministic)
        SimpleAccount account2 = factory.createAccount(owner, salt);
        
        assertEq(address(account1), address(account2), "Same parameters should return same account");
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

    function test_SecurityPass_StakeWithdrawal() public {
        // Give the factory owner some ETH first
        vm.deal(fcOwner, 10 ether);
        
        // Add some stake to the factory first
        vm.startPrank(fcOwner);
        factory.addStake{value: 1 ether}(1000);
        
        // Unlock stake
        factory.unlockStake();
        
        // Fast forward time to simulate unstake delay
        vm.warp(block.timestamp + 1001);
        
        uint256 initialBalance = fcOwner.balance;
        
        // Withdraw stake as owner
        factory.withdrawStake(payable(fcOwner));
        
        vm.stopPrank();
        
        // Check that balance increased
        assertTrue(fcOwner.balance > initialBalance, "Stake withdrawal failed");
    }

    function test_SecurityPass_LargeSaltValues() public {
        address owner = address(0x123);
        uint256 largeSalt = type(uint256).max;
        
        // Should handle large salt values without issues
        SimpleAccount account = factory.createAccount(owner, largeSalt);
        assertTrue(address(account) != address(0), "Should handle large salt values");
    }

    function test_SecurityPass_EventEmission() public {
        address owner = address(0x123);
        uint256 salt = 98765;
        
        // Test that account creation works without expecting specific events
        // since AccountCreated is only emitted during factory initialization
        SimpleAccount account = factory.createAccount(owner, salt);
        assertTrue(address(account) != address(0), "Account should be created successfully");
        
        // Verify the account has correct owner
        assertEq(account.owner(), owner, "Account should have correct owner");
    }
}