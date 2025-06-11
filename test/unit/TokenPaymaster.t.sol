// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/interfaces/PackedUserOperation.sol";
import "../../src/TokenPaymaster.sol";
import {MockOracle} from "../../src/utils/MockOracle.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SimpleAccountFactory} from "../../src/SimpleAccountFactory.sol";

contract TokenPaymasterTest is Test {
    using stdStorage for StdStorage;

    IEntryPoint public immutable entrypoint = IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    SimpleAccountFactory factory = new SimpleAccountFactory(entrypoint);

    PackedUserOperation public testUserOp = PackedUserOperation({
        sender: address(0x123),
        nonce: 1,
        initCode: hex"636F6E7374727563746F722875696E7429",
        callData: hex"65786563757465286279746573206461746129",
        accountGasLimits: bytes32("7D0"),
        preVerificationGas: 1_000,
        gasFees: bytes32("2710"),
        paymasterAndData: hex"68D985441429561E1d8eb9274A0483462B229FBb",
        signature: hex"8B89386EA80D89"
    });

    //Token used to pay gas
    IERC20Metadata gasToken = IERC20Metadata(vm.envAddress("GAS_TOKEN"));
    //Wrapped native token to swap from gas token to native token
    IERC20 wrappedNative = IERC20(vm.envAddress("W_NATIVE"));
    //UniSwap router to swap gas
    ISwapRouter swapRouter = ISwapRouter(vm.envAddress("UNISWAP_ROUTER"));

    //TokenPaymaster configuration
    TokenPaymaster.TokenPaymasterConfig public tokenPaymasterConfig = TokenPaymaster.TokenPaymasterConfig({
        priceMarkup: 1e26,           // 100% markup (no-profit)
        minEntryPointBalance: 0, // Minimum balance before swapping tokens
        refundPostopCost: 40000,       // Gas cost for refund operations
        priceMaxAge: 86400             // Price valid for 1 day (in seconds)
    });

    //ETH/usd oracle price: 1 ETH = $2000
    MockOracle public ethOracle = new MockOracle(200000000000, 8);

    //token/usd oracle price: 1 token = $1
    MockOracle public tokenOracle = new MockOracle(100000000, 8);
    
    // Oracle Helper configuration
    OracleHelper.OracleHelperConfig public oracleHelperConfig = OracleHelper.OracleHelperConfig({
        cacheTimeToLive: 300,          // Cache price for 5 minutes
        maxOracleRoundAge: 1800,       // Maximum age of oracle data (30 minutes)
        nativeOracle: ethOracle,
        nativeOracleReverse: false,    // Set to true if oracle returns token/ETH instead of ETH/token
        priceUpdateThreshold: 1e25,    // Update price if it changes by 10%
        tokenOracle: tokenOracle,
        tokenOracleReverse: false,     // Set to true if oracle returns ETH/token instead of token/ETH
        tokenToNativeOracle: false     // Set to true if using direct token/native oracle
    });
    
    // Uniswap Helper configuration
    UniswapHelper.UniswapHelperConfig public uniswapHelperConfig = UniswapHelper.UniswapHelperConfig({
        minSwapAmount: 0.01 ether,     // Minimum amount to swap
        slippage: 5,                   // 5% slippage tolerance
        uniswapPoolFee: 3000           // 0.3% pool fee (3000 = 0.3%)
    });

    function newTokenPaymaster(address owner) public returns (TokenPaymaster) {
        return new TokenPaymaster(
            gasToken,
            12,  //18 - 12 = 6 token decimals
            entrypoint,
            wrappedNative,
            swapRouter,
            tokenPaymasterConfig,
            oracleHelperConfig,
            uniswapHelperConfig,
            owner  // Set the contract owner to the deployer
        );
    }

    function test_setTokenPaymasterConfig_success() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        TokenPaymaster.TokenPaymasterConfig memory newTpc = TokenPaymaster.TokenPaymasterConfig({
            priceMarkup: 1.5e26,           // 150% markup (50% profit)
            minEntryPointBalance: 0.01 ether, // Minimum balance before swapping tokens
            refundPostopCost: 10000,       // Gas cost for refund operations
            priceMaxAge: 300             // Price valid for 5 minutes (in seconds)
        });
        
        vm.prank(owner);
        p.setTokenPaymasterConfig(newTpc);
        (uint priceMarkup, uint128 minEntryPointBalance, uint48 refundPostopCost, uint48 priceMaxAge) = p.tokenPaymasterConfig();
        assertEq(priceMarkup, newTpc.priceMarkup);
        assertEq(minEntryPointBalance, newTpc.minEntryPointBalance);
        assertEq(refundPostopCost, newTpc.refundPostopCost);
        assertEq(priceMaxAge, newTpc.priceMaxAge);
    }

    function test_setTokenPaymasterConfig_failOn_noOwnerCall() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        TokenPaymaster.TokenPaymasterConfig memory newTpc = TokenPaymaster.TokenPaymasterConfig({
            priceMarkup: 1.5e26,           // 150% markup (50% profit)
            minEntryPointBalance: 0.01 ether, // Minimum balance before swapping tokens
            refundPostopCost: 10000,       // Gas cost for refund operations
            priceMaxAge: 300             // Price valid for 5 minutes (in seconds)
        });
        
        address unauthorized = address(0x456);
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", unauthorized)
        );
        vm.prank(unauthorized);
        p.setTokenPaymasterConfig(newTpc);
    }

    function test_setTokenPaymasterConfig_failOn_priceMarkup_higherThan_200percent() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        TokenPaymaster.TokenPaymasterConfig memory newTpc = tokenPaymasterConfig;
        newTpc.priceMarkup = 2.1e26;  // 210% markup (110% profit)

        vm.expectRevert(bytes("TPM: price markup too high"));
        vm.prank(owner);
        p.setTokenPaymasterConfig(newTpc);
    }

    function test_setTokenPaymasterConfig_failOn_priceMarkup_lowerThan_100percent() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        TokenPaymaster.TokenPaymasterConfig memory newTpc = tokenPaymasterConfig;
        newTpc.priceMarkup = 0.9e26;  // 90% markup (10% loss)

        vm.expectRevert(bytes("TPM: price markup too low"));
        vm.prank(owner);
        p.setTokenPaymasterConfig(newTpc);
    }

    function test_setTokenDecimals_failOn_noOwnerCall() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        address unauthorized = address(0x456);
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", unauthorized)
        );
        vm.prank(unauthorized);
        p.setTokenDecimals(2);
    }

    function test_setTokenDecimals_success() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        vm.prank(owner);
        p.setTokenDecimals(2);

        assertEq(p.tokenDecimalsPower(), 10 ** 2);
    }

    function test_setUniswapConfiguration_failOn_noOwnerCall() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        UniswapHelper.UniswapHelperConfig memory newConfig = UniswapHelper.UniswapHelperConfig({
            minSwapAmount: 0.1 ether,     // Minimum amount to swap
            slippage: 10,                   // 10% slippage tolerance
            uniswapPoolFee: 9000           // 0.9% pool fee (9000 = 0.9%)
        });

        address unauthorized = address(0x456);
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", unauthorized)
        );
        vm.prank(unauthorized);
        p.setUniswapConfiguration(newConfig);
    }

    function test_setUniswapConfiguration_success() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        UniswapHelper.UniswapHelperConfig memory newConfig = UniswapHelper.UniswapHelperConfig({
            minSwapAmount: 0.1 ether,     // Minimum amount to swap
            slippage: 10,                   // 10% slippage tolerance
            uniswapPoolFee: 9000           // 0.9% pool fee (9000 = 0.9%)
        });

        vm.prank(owner);
        p.setUniswapConfiguration(newConfig);
    }

    function test_withdrawToken_failOn_noOwnerCall() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        //fund paymaster with 10 gas tokens
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(address(p))
            .checked_write(10e6);
        
        address unauthorized = address(0x456);
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", unauthorized)
        );
        vm.prank(unauthorized);
        p.withdrawToken(unauthorized, 5e6);
    }

    function test_withdrawToken_failOn_notEnoughAmount() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        //fund paymaster with 10 gas tokens
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(address(p))
            .checked_write(10e6);
        
        vm.expectRevert(abi.encodeWithSelector(
            bytes4(0xe450d38c),  //Insufficient balance error selector
            address(p),
            uint(10e6),
            uint(11e6)
        ));
        vm.prank(owner);
        p.withdrawToken(owner, 11e6);
    }

    function test_withdrawToken_success_toOwner() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        //fund paymaster with 10 gas tokens
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(address(p))
            .checked_write(10e6);
        
        assertEq(gasToken.balanceOf(owner), 0);
        vm.prank(owner);
        p.withdrawToken(owner, 10e6);

        assertEq(gasToken.balanceOf(owner), 10e6);
    }

    function test_withdrawToken_success_toAnother() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        //fund paymaster with 10 gas tokens
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(address(p))
            .checked_write(10e6);
        
        address benefitiary = address(0x456);
        assertEq(gasToken.balanceOf(benefitiary), 0);
        vm.prank(owner);
        p.withdrawToken(benefitiary, 10e6);

        assertEq(gasToken.balanceOf(benefitiary), 10e6);
    }

    function test_validatePaymasterUserOp_failOn_senderIsNotEntrypoint() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        vm.expectRevert(bytes("Sender not EntryPoint"));
        p.validatePaymasterUserOp(testUserOp, "", 0);
    }

    function test_validatePaymasterUserOp_failOn_paymasterAndData_empty() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.paymasterAndData = hex""; //empty data

        vm.expectRevert(bytes("TPM: invalid data length"));
        vm.prank(address(entrypoint));
        p.validatePaymasterUserOp(modifiedUserOp, "", 0);
    }

    function test_validatePaymasterUserOp_failOn_paymasterAndData_haveInvalidData() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.paymasterAndData = hex"1234"; //random data

        vm.expectRevert(bytes("TPM: invalid data length"));
        vm.prank(address(entrypoint));
        p.validatePaymasterUserOp(modifiedUserOp, "", 0);
    }

    function test_validatePaymasterUserOp_success_withoutReceiver() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.paymasterAndData = abi.encodePacked(address(p), uint(0)); //address + empty suffix

        vm.prank(address(entrypoint));
        (, uint256 validationResult) = p.validatePaymasterUserOp(modifiedUserOp, "", 0);

        //check if validationResult ends with 0 (success)
        assertEq(validationResult % 10, 0);
    }

    function test_validatePaymasterUserOp_failOn_ReceiverNotAccount() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.paymasterAndData = abi.encodePacked(address(p), uint(0), abi.encode(address(0x456))); //send random as receiver address

        vm.expectRevert();
        vm.prank(address(entrypoint));
        p.validatePaymasterUserOp(modifiedUserOp, "", 0);
    }

    function test_validatePaymasterUserOp_failOn_ReceiverRejectPay() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        vm.startPrank(address(0x123));
        SimpleAccount acc = factory.createAccount(address(0x123), 123456);
        //check receiver account will reject payment
        assertEq(acc.letCollectOnDeliver(), false);
        vm.stopPrank();

        PackedUserOperation memory modifiedUserOp = testUserOp;
        modifiedUserOp.paymasterAndData = abi.encodePacked(address(p), uint(0), abi.encode(address(acc))); //send account as receiver

        vm.expectRevert("PAE: cant pay");
        vm.prank(address(entrypoint));
        p.validatePaymasterUserOp(modifiedUserOp, "", 0);
    }

    function test_validatePaymasterUserOp_failOn_toIsNotReceiver() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        //Set account to accept to pay
        vm.startPrank(address(0x123));
        SimpleAccount acc = factory.createAccount(address(0x123), 123456);
        acc.setCollectOnDeliver(true);
        assertEq(acc.letCollectOnDeliver(), true);
        vm.stopPrank();

        PackedUserOperation memory modifiedUserOp = testUserOp;
        //set on callData: execute functon, transfer random address, 5 tokens (6 decimals)
        modifiedUserOp.callData = bytes.concat(
            SimpleAccount.execute.selector,
            abi.encode(address(0x789)),
            abi.encode(uint(5e6))
        );
        modifiedUserOp.paymasterAndData = abi.encodePacked(address(p), uint(0), abi.encode(address(acc))); //send account as receiver

        vm.expectRevert("PAE: invalid pay");
        vm.prank(address(entrypoint));
        p.validatePaymasterUserOp(modifiedUserOp, "", 0);
    }

    function test_validatePaymasterUserOp_returns_receiverAddress() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        //Set account to accept to pay
        vm.startPrank(address(0x123));
        SimpleAccount acc = factory.createAccount(address(0x123), 123456);
        acc.setCollectOnDeliver(true);
        assertEq(acc.letCollectOnDeliver(), true);
        vm.stopPrank();

        PackedUserOperation memory modifiedUserOp = testUserOp;
        //set on callData: execute functon, transfer random address, 5 tokens (6 decimals)
        modifiedUserOp.callData = bytes.concat(
            SimpleAccount.execute.selector,
            abi.encode(address(acc)),
            abi.encode(uint(5e6))
        );
        modifiedUserOp.paymasterAndData = abi.encodePacked(address(p), uint(0), abi.encode(address(acc))); //send account as receiver

        vm.prank(address(entrypoint));
        (bytes memory context, uint256 validationResult) = p.validatePaymasterUserOp(modifiedUserOp, "", 0);

        assertEq(validationResult % 10, 0);
        
        //Check receiver and sender are in context
        (address userOpSender, address receiver) = abi.decode(context, (address, address));
        assertEq(userOpSender, modifiedUserOp.sender);
        assertEq(receiver, address(acc));
    }

    function test_postOp_failOn_noEntrypointCall() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        vm.expectRevert(bytes("Sender not EntryPoint"));
        p.postOp(IPaymaster.PostOpMode.opSucceeded, abi.encode(address(0x456), address(0x789)), 1_000, 1_000);
    }

    function test_postOp_failOn_chargeNotApprovedTokens() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        uint actualGasCost = 0.0001 ether;
        uint actualUserOpFeePerGas = 1_000;

        address sender = address(0x456);
        address receiver = address(0x789);
        //fund receiver with 10 gas tokens
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(receiver)
            .checked_write(10e6);

        vm.expectRevert();
        vm.prank(address(entrypoint));
        p.postOp(IPaymaster.PostOpMode.opSucceeded, abi.encode(sender, receiver), actualGasCost, actualUserOpFeePerGas);
    }

    function test_postOp_chargesToReceiver() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);

        uint actualGasCost = 0.0001 ether;
        uint actualUserOpFeePerGas = 1_000;

        address sender = address(0x456);
        address receiver = address(0x789);
        //fund receiver with 10 gas tokens
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(receiver)
            .checked_write(10e6);

        //Aprove 5 gas tokens to paymaster
        vm.prank(receiver);
        gasToken.approve(address(p), 5e6);

        vm.prank(address(entrypoint));
        p.postOp(IPaymaster.PostOpMode.opSucceeded, abi.encode(sender, receiver), actualGasCost, actualUserOpFeePerGas);
        console.log(gasToken.balanceOf(receiver));
    }
}