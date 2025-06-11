// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/TokenPaymaster.sol";
import "../src/utils/MockOracle.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

contract TokenPaymasterScript is Script {
    // EntryPoint contract (v0.7)
    IEntryPoint constant ENTRYPOINT =
        IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    
    //Wormhole contracts
    mapping(uint256 => address) private cores;
    mapping(uint256 => address) private relayers;
    mapping(uint256 => address) private bridges;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // Fetch the private key from environment variables

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

        //Token used to pay gas
        IERC20Metadata gasToken = IERC20Metadata(vm.envAddress("GAS_TOKEN"));
        //Wrapped native token to swap from gas token to native token
        IERC20 wrappedNative = IERC20(vm.envAddress("W_NATIVE"));
        //UniSwap router to swap gas
        ISwapRouter swapRouter = ISwapRouter(vm.envAddress("UNISWAP_ROUTER"));
        
        //TokenPaymaster configuration
        TokenPaymaster.TokenPaymasterConfig memory tokenPaymasterConfig = TokenPaymaster.TokenPaymasterConfig({
            priceMarkup: 1e26,           // 100% markup (no-profit)
            minEntryPointBalance: 0.00001 ether, // Minimum balance before swapping tokens
            refundPostopCost: 40000,       // Gas cost for refund operations
            priceMaxAge: 86400             // Price valid for 1 day (in seconds)
        });

        vm.startBroadcast(deployerPrivateKey); // Start broadcasting transactions

        //ETH/usd oracle price: 1 ETH = $2000
        MockOracle ethOracle = new MockOracle(200000000000, 8);

        //token/usd oracle price: 1 token = $1
        MockOracle tokenOracle = new MockOracle(100000000, 8);
        
        // Oracle Helper configuration
        OracleHelper.OracleHelperConfig memory oracleHelperConfig = OracleHelper.OracleHelperConfig({
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
        UniswapHelper.UniswapHelperConfig memory uniswapHelperConfig = UniswapHelper.UniswapHelperConfig({
            minSwapAmount: 0.01 ether,     // Minimum amount to swap
            slippage: 5,                   // 5% slippage tolerance
            uniswapPoolFee: 3000           // 0.3% pool fee (3000 = 0.3%)
        });
        
        TokenPaymaster tokenPaymaster = new TokenPaymaster(
            gasToken,
            12,  //Gas token decimals for USDT
            ENTRYPOINT,
            wrappedNative,
            swapRouter,
            tokenPaymasterConfig,
            oracleHelperConfig,
            uniswapHelperConfig,
            msg.sender,  // Set the contract owner to the deployer
            relayers[block.chainid],
            bridges[block.chainid],
            cores[block.chainid]
        );
        console.log("TokenPaymaster deployed at:", address(tokenPaymaster));

        vm.stopBroadcast(); // Stop broadcasting transactions
    }
}