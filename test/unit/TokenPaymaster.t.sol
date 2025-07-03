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
    address fcOwner = address(0x173);
    SimpleAccountFactory factory = new SimpleAccountFactory(entrypoint, fcOwner);

    PackedUserOperation public testUserOp = PackedUserOperation({
        sender: address(0x169),
        nonce: 1,
        initCode: hex"636F6E7374727563746F722875696E7429",
        callData: hex"65786563757465286279746573206461746129",
        accountGasLimits: bytes32("7D0"),
        preVerificationGas: 1_000,
        gasFees: bytes32("2710"),
        paymasterAndData: abi.encodePacked(0x68D985441429561E1d8eb9274A0483462B229FBb, uint128(10), uint128(41000)),
        signature: hex"8B89386EA80D89"
    });

    //Token to execute crosschain transfers: Testnet USDC
    IERC20 transferToken = IERC20(0x5fd84259d66Cd46123540766Be93DFE6D43130D7);
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

    //Wormhole contracts
    mapping(uint256 => address) private cores;
    mapping(uint256 => address) private relayers;
    mapping(uint256 => address) private bridges;

    function newTokenPaymaster(address owner) public returns (TokenPaymaster) {
        //Wormhole OP sepolia contracts
        cores[11155420] = 0x31377888146f3253211EFEf5c676D41ECe7D58Fe;
        relayers[11155420] = 0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE;
        bridges[11155420] = 0x99737Ec4B815d816c49A385943baf0380e75c0Ac;

        //Wormhole Polygon Amoy contracts
        cores[80002] = 0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35;
        relayers[80002] = 0x362fca37E45fe1096b42021b543f462D49a5C8df;
        bridges[80002] = 0xC7A204bDBFe983FCD8d8E61D02b475D4073fF97e;

        //Wormhole Base Sepolia contracts
        cores[84532] = 0x79A1027a6A159502049F10906D333EC57E95F083;
        relayers[84532] = 0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE;
        bridges[84532] = 0x86F55A04690fd7815A3D802bD587e83eA888B239;

        //Wormhole Arbitrum Sepolia contracts
        cores[421614] = 0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35;
        relayers[421614] = 0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470;
        bridges[421614] = 0xC7A204bDBFe983FCD8d8E61D02b475D4073fF97e;

        require(cores[block.chainid] != address(0), "Chain not supported");

        return new TokenPaymaster(
            gasToken,
            12,  //18 - 12 = 6 token decimals
            entrypoint,
            wrappedNative,
            swapRouter,
            tokenPaymasterConfig,
            oracleHelperConfig,
            uniswapHelperConfig,
            owner,  // Set the contract owner to the deployer
            relayers[block.chainid],
            bridges[block.chainid],
            cores[block.chainid]
        );
    }

    function test_setTokenPaymasterConfig_success() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

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
        factory.initialize(address(p));

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
        factory.initialize(address(p));

        TokenPaymaster.TokenPaymasterConfig memory newTpc = tokenPaymasterConfig;
        newTpc.priceMarkup = 2.1e26;  // 210% markup (110% profit)

        vm.expectRevert(bytes("TPM: price markup too high"));
        vm.prank(owner);
        p.setTokenPaymasterConfig(newTpc);
    }

    function test_setTokenPaymasterConfig_failOn_priceMarkup_lowerThan_100percent() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

        TokenPaymaster.TokenPaymasterConfig memory newTpc = tokenPaymasterConfig;
        newTpc.priceMarkup = 0.9e26;  // 90% markup (10% loss)

        vm.expectRevert(bytes("TPM: price markup too low"));
        vm.prank(owner);
        p.setTokenPaymasterConfig(newTpc);
    }

    function test_setTokenDecimals_failOn_noOwnerCall() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

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
        factory.initialize(address(p));

        vm.prank(owner);
        p.setTokenDecimals(2);

        assertEq(p.tokenDecimalsPower(), 10 ** 2);
    }

    function test_setUniswapConfiguration_failOn_noOwnerCall() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

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
        factory.initialize(address(p));

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
        factory.initialize(address(p));

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
        factory.initialize(address(p));

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
        factory.initialize(address(p));

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
        factory.initialize(address(p));

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
        factory.initialize(address(p));

        vm.expectRevert(bytes("Sender not EntryPoint"));
        p.validatePaymasterUserOp(testUserOp, "", 0);
    }

    function test_validatePaymasterUserOp_failOn_senderWithoutGas() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

        p.updateCachedPrice(false);
        vm.expectRevert(bytes("Not enough gas"));
        vm.prank(address(entrypoint));
        p.validatePaymasterUserOp(testUserOp, "", 4e12); //there must be at least 0.008 USDT
    }

    function test_validatePaymasterUserOp_failOn_senderWithoutApprovedGas() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

        //fund sender with 10 gas tokens
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(testUserOp.sender)
            .checked_write(10e6);

        p.updateCachedPrice(false);
        vm.expectRevert(bytes("Not enough gas allowance"));
        vm.prank(address(entrypoint));
        p.validatePaymasterUserOp(testUserOp, "", 4e12); //there must be at least 0.008 USDT
    }

    function test_validatePaymasterUserOp_returns_receiverAddress() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        p.updateCachedPrice(false);
        factory.initialize( address(p));

        PackedUserOperation memory modifiedUserOp = testUserOp;
        address receiver = address(0x456);

        //fund receiver with 10 gas tokens
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(receiver)
            .checked_write(10e6);

        //Aprove 5 gas tokens to paymaster
        vm.prank(receiver);
        gasToken.approve(address(p), 5e6);

        modifiedUserOp.callData = abi.encodeWithSelector(
            SimpleAccount.execute.selector,
            address(p),
            0,
            abi.encodeWithSelector(
                TokenPaymaster.transferReceiverPay.selector,
                receiver,
                0,
                5e4,
                address(gasToken)
            )
        );

        vm.prank(address(entrypoint));
        (bytes memory context, uint256 validationResult) = p.validatePaymasterUserOp(modifiedUserOp, "", 4e12);
        bool sigFailed = (validationResult & 1) != 0;
        assertEq(sigFailed, false);
        
        //Check receiver and sender are in context
        (address userOpSender, address toCharge) = abi.decode(context, (address, address));
        assertEq(userOpSender, modifiedUserOp.sender);
        assertEq(toCharge, receiver);
    }

    function test_postOp_failOn_noEntrypointCall() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

        vm.expectRevert(bytes("Sender not EntryPoint"));
        p.postOp(IPaymaster.PostOpMode.opSucceeded, abi.encode(address(0x456), address(0x789)), 1_000, 1_000);
    }

    function test_postOp_failOn_chargeNotApprovedTokens() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

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
        p.updateCachedPrice(false);
        factory.initialize(address(p));

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
    }

    function test_postOp_chargesCreateDebt() public {
        address owner = address(0x123);
        address accountOwner = address(0x456);

        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

        uint actualGasCost = 0.0001 ether;
        uint actualUserOpFeePerGas = 1_000;
        
        SimpleAccount account = factory.createAccount(accountOwner, 123456);
        assertGt(account.createDebt(), 0);
        //fund account with 10 gas tokens
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(address(account))
            .checked_write(10e6);
        
        //approve 5 gas tokens to paymaster
        bytes memory func = abi.encodeWithSignature("approve(address,uint256)", address(p), uint256(5e6));
        vm.prank(accountOwner);
        account.execute(address(gasToken), 0, func);
        assertEq(gasToken.allowance(address(account), address(p)), 5e6);

        vm.startPrank(address(entrypoint));
        p.postOp(IPaymaster.PostOpMode.opSucceeded, abi.encode(address(account), address(account)), actualGasCost, actualUserOpFeePerGas);
        assertEq(account.createDebt(), 0);
        p.postOp(IPaymaster.PostOpMode.opSucceeded, abi.encode(address(account), address(account)), actualGasCost, actualUserOpFeePerGas);
        vm.stopPrank();
    }

    function test_transferReceiverPay_failOn_ReceiverNotAccount() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

        vm.expectRevert();
        p.transferReceiverPay(
            address(0x826),
            1,
            address(0x879),
            1000,
            address(gasToken)
        );
    }

    function test_transferReceiverPay_failOn_ReceiverRejectPay() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

        vm.startPrank(address(0x456));
        SimpleAccount acc = factory.createAccount(address(0x456), 123456);
        //check receiver account will reject payment
        assertEq(acc.letCollectOnDeliver(), false);
        vm.stopPrank();

        vm.expectRevert("PAE: cant pay");
        p.transferReceiverPay(
            address(acc),
            1,
            address(0x879),
            1000,
            address(gasToken)
        );
    }

    function test_transferReceiverPay_failOn_SenderWithoutBalance() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

        vm.startPrank(address(0x456));
        SimpleAccount acc = factory.createAccount(address(0x456), 123456);
        acc.setCollectOnDeliver(true);
        assertEq(acc.letCollectOnDeliver(), true);
        vm.stopPrank();

        vm.expectRevert();
        p.transferReceiverPay(
            address(acc),
            0,
            address(0x879),
            5e4,
            address(gasToken)
        );
    }

    function test_transferReceiverPay_failOn_SenderWithoutApprovedBalance() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));

        vm.startPrank(address(0x456));
        SimpleAccount acc = factory.createAccount(address(0x456), 123456);
        acc.setCollectOnDeliver(true);
        assertEq(acc.letCollectOnDeliver(), true);
        vm.stopPrank();

        address sender = address(0x546);
        //fund sender with 10 gas tokens
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(sender)
            .checked_write(10e6);
        
        vm.expectRevert();
        vm.prank(sender);
        p.transferReceiverPay(
            address(acc),
            0,
            address(0x879),
            5e4,
            address(gasToken)
        );
    }

    function test_transferReceiverPay_success() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));
        p.updateCachedPrice(false);
        //fund payaster with native tokens for fee
        vm.deal(address(p), 0.5 ether);

        //create receiver wallet
        vm.startPrank(address(0x456));
        SimpleAccount acc = factory.createAccount(address(0x456), 123456);
        acc.setCollectOnDeliver(true);
        assertEq(acc.letCollectOnDeliver(), true);
        vm.stopPrank();

        //fund receiver with gas token for fee
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(address(acc))
            .checked_write(100e6);
        vm.prank(address(acc));
        gasToken.approve(address(p), 100e6);

        address sender = address(0x546);
        //fund sender with USDC to transfer
        stdstore.target(address(transferToken))
            .sig(transferToken.balanceOf.selector)
            .with_key(sender)
            .checked_write(10e6);

        vm.startPrank(sender);
        transferToken.approve(address(p), 1e6);
        
        p.transferReceiverPay(
            address(acc),
            10003,
            address(0x879),
            1e6,
            address(transferToken)
        );
        vm.stopPrank();

        assertEq(address(p).balance < 0.5 ether, true);
        assertEq(gasToken.balanceOf(address(acc)) < 100e6, true);
        assertEq(transferToken.allowance(sender, address(p)), 0);
        assertEq(transferToken.balanceOf(sender), 9e6);
    }

    function test_quoteCrossChainDeposit_return_inGasToken() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));
        p.updateCachedPrice(false);
        //check for arbitrum sepolia
        uint cost = p.quoteCrossChainDeposit(10003);
        //Cost must be in gas Token: USDT
        //On testnets, gas is high
        //With 1 ETH = 2000 USDT, cost must be near 30 USDT
        assertEq(cost >= 20e6, true);
        assertEq(cost <= 40e6, true);
    }

    function test_sendCrossChainDeposit_failOn_senderIsAny() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));
        p.updateCachedPrice(false);

        address sender = address(0x246);

        vm.expectRevert(bytes("Sender must be contract itself or msg.sender"));
        vm.startPrank(sender);
        p.sendCrossChainDeposit(
            10003,
            address(0x879),
            address(0x789),     //sender is not msg.sender
            address(0x912),
            1e6,
            address(transferToken)
        );
    }

    function test_sendCrossChainDeposit_failOn_senderWithoutGas() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));
        p.updateCachedPrice(false);

        address sender = address(0x246);

        vm.expectRevert();
        vm.prank(sender);
        p.sendCrossChainDeposit(
            10003,
            address(0x879),
            address(sender),
            address(0x912),
            1e6,
            address(transferToken)
        );
    }

    function test_sendCrossChainDeposit_failOn_senderWithoutApprovedGas() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));
        p.updateCachedPrice(false);

        address sender = address(0x246);
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(sender)
            .checked_write(100e6);

        vm.expectRevert();
        vm.prank(sender);
        p.sendCrossChainDeposit(
            10003,
            address(0x879),
            address(sender),
            address(0x912),
            1e6,
            address(transferToken)
        );
    }

    function test_sendCrossChainDeposit_failOn_senderWithoutTokenToSend() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));
        p.updateCachedPrice(false);

        address sender = address(0x246);
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(sender)
            .checked_write(100e6);

        vm.startPrank(sender);
        gasToken.approve(address(p), 90e6);
        transferToken.approve(address(p), 1e6);
        
        vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
        p.sendCrossChainDeposit(
            10003,
            address(0x879),
            address(sender),
            address(0x912),
            1e6,
            address(transferToken)
        );
        vm.stopPrank();
    }

    function test_sendCrossChainDeposit_failOn_senderWithoutApprovedTokenToSend() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));
        p.updateCachedPrice(false);

        address sender = address(0x246);
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(sender)
            .checked_write(100e6);
        stdstore.target(address(transferToken))
            .sig(transferToken.balanceOf.selector)
            .with_key(sender)
            .checked_write(10e6);

        vm.startPrank(sender);
        gasToken.approve(address(p), 90e6);
        
        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));
        p.sendCrossChainDeposit(
            10003,
            address(0x879),
            address(sender),
            address(0x912),
            1e6,
            address(transferToken)
        );
        vm.stopPrank();
    }

    function test_sendCrossChainDeposit_success() public {
        address owner = address(0x123);
        TokenPaymaster p = newTokenPaymaster(owner);
        factory.initialize(address(p));
        p.updateCachedPrice(false);

        //fund paymaster with native tokens
        vm.deal(payable(address(p)), 0.5 ether);

        address sender = address(0x246);
        //fund sender with gas and USDC to transfer
        stdstore.target(address(gasToken))
            .sig(gasToken.balanceOf.selector)
            .with_key(sender)
            .checked_write(100e6);
        stdstore.target(address(transferToken))
            .sig(transferToken.balanceOf.selector)
            .with_key(sender)
            .checked_write(10e6);

        vm.startPrank(sender);
        gasToken.approve(address(p), 90e6);
        transferToken.approve(address(p), 1e6);
        
        p.sendCrossChainDeposit(
            10003,
            address(0x879),
            address(sender),
            address(0x912),
            1e6,
            address(transferToken)
        );
        vm.stopPrank();

        assertEq(address(p).balance < 0.5 ether, true);
        assertEq(gasToken.balanceOf(sender) < 100e6, true);
        assertEq(transferToken.allowance(sender, address(p)), 0);
        assertEq(transferToken.balanceOf(sender), 9e6);
    }
}