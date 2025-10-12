// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/SimpleAccount.sol";
import "../../src/SimpleAccountV2.sol";
import "@account-abstraction/core/EntryPoint.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SimpleAccountV2Test is Test {
    SimpleAccount public implementation;
    SimpleAccountV2 public implementationV2;
    SimpleAccount public proxy;
    EntryPoint public entryPoint;
    address payable public owner;
    address public factory;
    address public tokenPaymaster;

    event SimpleAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    
    function setUp() public {
        // Deploy contracts
        owner = payable(address(0x1234));
        factory = address(0x5678);
        tokenPaymaster = address(0x9ABC);
        entryPoint = new EntryPoint();
        
        // Deploy implementations
        implementation = new SimpleAccount(entryPoint);
        implementationV2 = new SimpleAccountV2(entryPoint, tokenPaymaster);
        
        // Deploy and initialize proxy
        bytes memory initData = abi.encodeWithSelector(
            SimpleAccount.initialize.selector,
            owner,
            factory
        );
        
        ERC1967Proxy proxyContract = new ERC1967Proxy(
            address(implementation),
            initData
        );
        
        proxy = SimpleAccount(payable(address(proxyContract)));
        vm.label(address(proxy), "Proxy");
    }

    function test_InitialState() public view {
        assertEq(proxy.owner(), owner);
        assertEq(address(proxy.entryPoint()), address(entryPoint));
    }

    function test_UpgradeToV2() public {
        // Test V1 functionality first
        vm.startPrank(owner);
        proxy.setCollectOnDeliver(true);
        assertTrue(proxy.letCollectOnDeliver());
        vm.stopPrank();

        // Upgrade to V2
        vm.prank(owner);
        proxy.upgradeToAndCall(address(implementationV2), "");
        
        // Cast proxy to V2 type
        SimpleAccountV2 proxyV2 = SimpleAccountV2(payable(address(proxy)));
        
        // Verify state is preserved
        assertEq(proxyV2.owner(), owner);
        assertEq(proxyV2.factory(), factory);
        assertTrue(proxyV2.letCollectOnDeliver());
    }

    function test_UpgradeOnlyOwner() public {
        vm.expectRevert("only owner");
        vm.prank(address(0xBEEF));
        proxy.upgradeToAndCall(address(implementationV2), "");
    }

    function test_idGuardian_notOwner() public {
        // Upgrade to V2
        vm.prank(owner);
        proxy.upgradeToAndCall(address(implementationV2), "");
        SimpleAccountV2 proxyV2 = SimpleAccountV2(payable(address(proxy)));

        address attacker = address(0x1617);
        // Set guardian
        vm.expectRevert(bytes("only owner"));
        vm.prank(attacker);
        proxyV2.setIdGuardian(address(0xDEAD));
    }

    function test_idGuardian_zeroAddress() public {
        // Upgrade to V2
        vm.prank(owner);
        proxy.upgradeToAndCall(address(implementationV2), "");
        SimpleAccountV2 proxyV2 = SimpleAccountV2(payable(address(proxy)));

        // Set guardian
        vm.expectRevert(bytes("zero addr"));
        vm.prank(owner);
        proxyV2.setIdGuardian(address(0x0));
    }
}