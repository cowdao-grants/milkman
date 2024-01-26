// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Surl} from "surl/Surl.sol";
import "../src/Milkman.sol";
import "../src/pricecheckers/UniV2ExpectedOutCalculator.sol";
import "../src/pricecheckers/CurveExpectedOutCalculator.sol";
import "../src/pricecheckers/UniV3ExpectedOutCalculator.sol";
import "../src/pricecheckers/ChainlinkExpectedOutCalculator.sol";
// import "../src/pricecheckers/SingleSidedBalancerBalWethExpectedOutCalculator.sol";
import "../src/pricecheckers/FixedSlippageChecker.sol";
import "../src/pricecheckers/DynamicSlippageChecker.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MilkmanTest is Test {
    using Surl for *;

    Milkman milkman;
    address sushiswapExpectedOutCalculator;
    address sushiswapPriceChecker;
    IERC20 fromToken;
    IERC20 toToken;
    uint256 amountIn;
    address priceChecker;
    address whale;

    bytes32 SWAP_REQUESTED_EVENT = keccak256("SwapRequested(address,address,uint256,address,address,address,address,bytes)");

    address SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    mapping(string => address) private tokenAddress;
    mapping(string => string) private sellToBuyMap;
    string[] private tokensToSell;
    mapping(string => uint256) private amounts;
    mapping(string => address) private whaleAddresses;

    function setUp() public {
        milkman = new Milkman();
        sushiswapExpectedOutCalculator = address(new UniV2ExpectedOutCalculator("SUSHISWAP_EXPECTED_OUT_CALCULATOR", SUSHISWAP_ROUTER));
        sushiswapPriceChecker = address(new FixedSlippageChecker("SUSHISWAP_500_BPS_PRICE_CHECKER", 500, sushiswapExpectedOutCalculator));
        
        tokenAddress["TOKE"] = 0x2e9d63788249371f1DFC918a52f8d799F4a38C94;
        tokenAddress["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddress["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokenAddress["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddress["GUSD"] = 0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd;
        tokenAddress["AAVE"] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
        tokenAddress["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddress["BAT"] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
        tokenAddress["ALCX"] = 0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF;
        tokenAddress["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddress["UNI"] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
        tokenAddress["BAL"] = 0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF;
        tokenAddress["BAL/WETH"] = 0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56;
        tokenAddress["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddress["COW"] = 0xDEf1CA1fb7FBcDC777520aa7f396b4E015F497aB;

        sellToBuyMap["TOKE"] = "DAI";
        sellToBuyMap["USDC"] = "USDT";
        sellToBuyMap["GUSD"] = "USDC";
        sellToBuyMap["AAVE"] = "WETH";
        sellToBuyMap["BAT"] = "ALCX";
        sellToBuyMap["WETH"] = "BAL/WETH";
        sellToBuyMap["UNI"] = "USDT";
        sellToBuyMap["ALCX"] = "TOKE";
        sellToBuyMap["BAL"] = "BAL/WETH";
        sellToBuyMap["YFI"] = "USDC";
        sellToBuyMap["USDT"] = "UNI";
        sellToBuyMap["COW"] = "DAI";

        amounts["TOKE"] = 80000; // 80,000 TOKE
        amounts["USDC"] = 5000000; // 5,000,000 USDC
        amounts["GUSD"] = 1000; // 1,000 GUSD
        amounts["AAVE"] = 2500; // 2,500 AAVE
        amounts["BAT"] = 280000; // 280,000 BAT
        amounts["WETH"] = 325; // 325 WETH
        amounts["UNI"] = 80000; // 80,000 UNI
        amounts["ALCX"] = 4000; // 4,000 ALCX
        amounts["BAL"] = 300000; // 300,000 BAL
        amounts["YFI"] = 3; // 3 YFI
        amounts["USDT"] = 2000000; // 2,000,000 USDT
        amounts["COW"] = 900000; // 900,000 COW

        whaleAddresses["GUSD"] = 0x5f65f7b609678448494De4C87521CdF6cEf1e932;
        // whaleAddresses["USDT"] = 0xa929022c9107643515f5c777ce9a910f0d1e490c;
        // whaleAddresses["WETH"] = 0x030ba81f1c18d280636f32af80b9aad02cf0854e;
        // whaleAddresses["WBTC"] = 0xccf4429db6322d5c611ee964527d42e5d685dd6a;
        whaleAddresses["DAI"] = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
        whaleAddresses["USDC"] = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
        whaleAddresses["LINK"] = 0x98C63b7B319dFBDF3d811530F2ab9DfE4983Af9D;
        whaleAddresses["GNO"] = 0x4f8AD938eBA0CD19155a835f617317a6E788c868;
        whaleAddresses["TOKE"] = 0x96F98Ed74639689C3A11daf38ef86E59F43417D3;
        whaleAddresses["AAVE"] = 0x4da27a545c0c5B758a6BA100e3a049001de870f5;
        whaleAddresses["BAT"] = 0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E;
        whaleAddresses["UNI"] = 0x1a9C8182C09F50C8318d769245beA52c32BE35BC;
        whaleAddresses["ALCX"] = 0x000000000000000000000000000000000000dEaD;
        whaleAddresses["BAL"] = 0x10A19e7eE7d7F8a52822f6817de8ea18204F2e4f;
        whaleAddresses["YFI"] = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
        // whaleAddresses["COW"] = 0xca771eda0c70aa7d053ab1b25004559b918fe662;

        // tokensToSell = ["TOKE", "USDC", "GUSD", "AAVE", "BAT", "WETH", "UNI", "ALCX", "BAL", "YFI", "USDT", "COW"];
        tokensToSell = ["TOKE"];
    }

    function testRequestSwapExactTokensForTokens() public {
        for (uint8 i = 0; i < tokensToSell.length; i++) {
            string memory tokenToSell = tokensToSell[i];
            string memory tokenToBuy = sellToBuyMap[tokenToSell];
            fromToken = IERC20(tokenAddress[tokenToSell]);
            toToken = IERC20(tokenAddress[tokenToBuy]);
            amountIn = amounts[tokenToSell] * 1e18;
            priceChecker = sushiswapPriceChecker;
            whale = whaleAddresses[tokenToSell];

            uint256 amountIn = amounts[tokenToSell] * 1e18;  

            vm.prank(whale);
            fromToken.approve(address(milkman), amountIn);

            vm.recordLogs();

            vm.prank(whale);
            milkman.requestSwapExactTokensForTokens(
                amountIn,
                fromToken,
                toToken,
                address(this), // Receiver address
                priceChecker,
                "" // priceCheckerData
            );

            Vm.Log[] memory entries = vm.getRecordedLogs();

            assertEq(entries[3].topics[0], SWAP_REQUESTED_EVENT);

            (address orderContract,,,,,,,) = (abi.decode(entries[3].data, (address,address,uint256,address,address,address,address,bytes)));

            assertEq(fromToken.balanceOf(orderContract), amountIn);

            bytes32 expectedSwapHash = keccak256(
                abi.encode(
                    whale,
                    address(this),
                    fromToken,
                    toToken,
                    amountIn,
                    priceChecker,
                    bytes("")
                )
            );
            assertEq(Milkman(orderContract).swapHash(), expectedSwapHash);

            string[] memory headers = new string[](1);
            headers[0] = "Content-Type: application/json";

            // (uint256 status, bytes memory data) = "https://httpbin.org/post".post(headers, 
            //     string(abi.encodePacked('{"foo": ', '"bar"}')));

            //   post_body = {
            //     "sellToken": sell_token.address,
            //     "buyToken": buy_token.address,
            //     "from": "0x5F4bd1b3667127Bf44beBBa9e5d736B65A1677E5",
            //     "kind": "sell",
            //     "sellAmountBeforeFee": str(sell_amount),
            //     "priceQuality": "fast",
            //     "signingScheme": "eip1271",
            //     "verificationGasLimit": 30000,
            // }

            (uint256 status, bytes memory data) = 
                "https://api.cow.fi/mainnet/api/v1/quote".post(headers, 
                string(abi.encodePacked(
                    '{"sellToken": "', vm.toString(address(fromToken)),
                    '", "buyToken": "', vm.toString(address(toToken)), 
                    '", "from": "', vm.toString(whale),
                    '", "kind": "sell", "sellAmountBeforeFee": "', vm.toString(amountIn),
                    '", "priceQuality": "fast", "signingScheme": "eip1271", "verificationGasLimit": 30000',
                    '}'
                )));

            console.log("data", string(data));

            assertEq(status, 200);

            // (uint256 status, bytes memory data) = "https://httpbin.org/get".get();
            // console.log("status", status);
            // console.log("body", string(data));
            

            // console.log(orderContract);
            // console.lo(fromToken.balanceOf(orderContract));

            // console.log("log", entries[3].topics.length);

            // assertEq(entries.length, 1);

            // vm.expectEmit(true, true, true, true);
        }
        // priceChecker = sushiswapPriceChecker;
        // Arrange: Set up the state before calling the function
        // uint256 amountIn = 1e18;  // Example amount

        // // Act: Call the function you want to test

        // Assert: Check the state after calling the function
        // Example: Assert that the swap was requested correctly
        // assertTrue(true);
    }

    // Additional test cases for different scenarios and edge cases
}
