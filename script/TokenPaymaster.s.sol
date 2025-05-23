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

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // Fetch the private key from environment variables

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

        vm.startBroadcast(deployerPrivateKey); // Start broadcasting transactions
        
        TokenPaymaster tokenPaymaster = new TokenPaymaster(
            gasToken,
            ENTRYPOINT,
            wrappedNative,
            swapRouter,
            tokenPaymasterConfig,
            oracleHelperConfig,
            uniswapHelperConfig,
            msg.sender  // Set the contract owner to the deployer
        );
        console.log("TokenPaymaster deployed at:", address(tokenPaymaster));

        vm.stopBroadcast(); // Stop broadcasting transactions
    }
}