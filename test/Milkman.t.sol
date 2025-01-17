// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.7.6;

pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Surl} from "surl/Surl.sol";
import "../src/Milkman.sol";
import "../src/pricecheckers/UniV2ExpectedOutCalculator.sol";
import "../src/pricecheckers/CurveExpectedOutCalculator.sol";
import "../src/pricecheckers/UniV3ExpectedOutCalculator.sol";
import "../src/pricecheckers/ChainlinkExpectedOutCalculator.sol";
import {SingleSidedBalancerBalWethExpectedOutCalculator} from
    "../src/pricecheckers/SingleSidedBalancerBalWethExpectedOutCalculator.sol";
import "../src/pricecheckers/MetaExpectedOutCalculator.sol";
import "../src/pricecheckers/FixedSlippageChecker.sol";
import "../src/pricecheckers/DynamicSlippageChecker.sol";
import "../src/pricecheckers/FixedMinOutPriceChecker.sol";
import {IPriceChecker} from "../interfaces/IPriceChecker.sol";
import {GPv2Order} from "@cow-protocol/contracts/libraries/GPv2Order.sol";
import {IERC20 as CoWIERC20} from "@cow-protocol/contracts/interfaces/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}

contract MilkmanTest is Test {
    using Surl for *;
    using stdJson for string;
    using GPv2Order for GPv2Order.Data;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    Milkman milkman;
    IERC20 fromToken;
    IERC20 toToken;
    uint256 amountIn;
    address whale;
    address priceChecker;
    bytes priceCheckerData;

    address chainlinkExpectedOutCalculator;
    address curveExpectedOutCalculator;
    address sushiswapExpectedOutCalculator;
    address ssbBalWethExpectedOutCalculator;
    address univ3ExpectedOutCalculator;
    address metaExpectedOutCalculator;
    address chainlinkPriceChecker;
    address curvePriceChecker;
    address sushiswapPriceChecker;
    address univ3PriceChecker;
    address metaPriceChecker;
    address ssbBalWethPriceChecker;
    address fixedMinOutPriceChecker;

    bytes32 public constant APP_DATA = 0x2B8694ED30082129598720860E8E972F07AA10D9B81CAE16CA0E2CFB24743E24;
    bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant NON_MAGIC_VALUE = 0xffffffff;

    bytes internal constant ZERO_BYTES = bytes("0");

    bytes32 public constant SWAP_REQUESTED_EVENT =
        keccak256("SwapRequested(address,address,uint256,address,address,address,bytes32,address,bytes)");

    address SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    mapping(string => address) private tokenAddress;
    mapping(string => string) private sellToBuyMap;
    mapping(string => uint256) private amounts;
    mapping(string => address) private whaleAddresses;
    mapping(string => address) private priceCheckers;
    mapping(string => bytes) public priceCheckerDatas;

    function univ2ExpectedOutData() internal pure returns (bytes memory) {
        return ZERO_BYTES;
    }

    function curveExpectedOutData() internal pure returns (bytes memory) {
        return ZERO_BYTES;
    }

    function ssbWethExpectedOutData() internal pure returns (bytes memory) {
        return ZERO_BYTES;
    }

    function chainlinkExpectedOutData(address[] memory priceFeeds, bool[] memory reverses) internal pure returns (bytes memory) {
        return abi.encode(priceFeeds, reverses);
    }

    function univ3ExpectedOutData(address[] memory swapPath, uint24[] memory poolFees) internal pure returns (bytes memory) {
        return abi.encode(swapPath, poolFees);
    }

    function metaExpectedOutData(address[] memory swapPath, address[] memory expectedOutCalculators, bytes[] memory expectedOutCalculatorData) internal pure returns (bytes memory) {
        return abi.encode(swapPath, expectedOutCalculators, expectedOutCalculatorData);
    }

    function parseUint(string memory json, string memory key) internal pure returns (uint256) {
        bytes memory valueBytes = vm.parseJson(json, key);
        string memory valueString = abi.decode(valueBytes, (string));
        return vm.parseUint(valueString);
    }

    function dynamicSlippagePriceCheckerData(uint256 allowedSlippageBips, bytes memory expectedOutData) internal pure returns (bytes memory) {
        return abi.encode(allowedSlippageBips, expectedOutData);
    }

    function fixedMinOutPriceCheckerData(uint256 minOut) internal pure returns (bytes memory) {
        return abi.encode(minOut);
    }

    function setUp() public {
        milkman = new Milkman();
        chainlinkExpectedOutCalculator = address(new ChainlinkExpectedOutCalculator());
        curveExpectedOutCalculator = address(new CurveExpectedOutCalculator());

        sushiswapExpectedOutCalculator = address(
            new UniV2ExpectedOutCalculator(
                                                "SUSHI_EXPECTED_OUT_CALCULATOR",
                                                0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F // Sushi Router
                                            )
        );

        ssbBalWethExpectedOutCalculator = address(new SingleSidedBalancerBalWethExpectedOutCalculator());
        univ3ExpectedOutCalculator = address(new UniV3ExpectedOutCalculator());
        metaExpectedOutCalculator = address(new MetaExpectedOutCalculator());

        chainlinkPriceChecker = address(
            new DynamicSlippageChecker(
                                                "CHAINLINK_DYNAMIC_SLIPPAGE_PRICE_CHECKER",
                                                chainlinkExpectedOutCalculator
                                            )
        );

        curvePriceChecker = address(
            new DynamicSlippageChecker(
                                                "CURVE_DYNAMIC_SLIPPAGE_PRICE_CHECKER",
                                                curveExpectedOutCalculator
                                            )
        );

        sushiswapPriceChecker = address(
            new FixedSlippageChecker(
                                                "SUSHISWAP_STATIC_500_BPS_SLIPPAGE_PRICE_CHECKER",
                                                500, // 5% slippage
                                                sushiswapExpectedOutCalculator
                                            )
        );

        univ3PriceChecker = address(
            new DynamicSlippageChecker(
                                                "UNIV3_DYNAMIC_SLIPPAGE_PRICE_CHECKER",
                                                univ3ExpectedOutCalculator
                                            )
        );

        metaPriceChecker = address(
            new DynamicSlippageChecker(
                                                "META_DYNAMIC_SLIPPAGE_PRICE_CHECKER",
                                                metaExpectedOutCalculator
                                            )
        );

        ssbBalWethPriceChecker = address(
            new DynamicSlippageChecker(
                                                "SSB_BAL_WETH_DYNAMIC_SLIPPAGE_PRICE_CHECKER",
                                                ssbBalWethExpectedOutCalculator
                                            )
        );

        fixedMinOutPriceChecker = address(new FixedMinOutPriceChecker());

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
        tokenAddress["BAL"] = 0xba100000625a3754423978a60c9317c58a424e3D;
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
        amounts["GUSD"] = 10_000; // 10,000 GUSD
        amounts["AAVE"] = 2500; // 2,500 AAVE
        amounts["BAT"] = 28000; // 28,000 BAT
        amounts["WETH"] = 325; // 325 WETH
        amounts["UNI"] = 80000; // 80,000 UNI
        amounts["ALCX"] = 4000; // 4,000 ALCX
        amounts["BAL"] = 300000; // 300,000 BAL
        amounts["YFI"] = 3; // 3 YFI
        amounts["USDT"] = 2000000; // 2,000,000 USDT
        amounts["COW"] = 900000; // 900,000 COW

        whaleAddresses["GUSD"] = 0x5f65f7b609678448494De4C87521CdF6cEf1e932;
        whaleAddresses["USDT"] = 0x5754284f345afc66a98fbB0a0Afe71e0F007B949;
        whaleAddresses["WETH"] = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;
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
        whaleAddresses["COW"] = 0xcA771eda0c70aA7d053aB1B25004559B918FE662;

        priceCheckers["TOKE"] = sushiswapPriceChecker;
        priceCheckers["USDC"] = curvePriceChecker;
        priceCheckers["GUSD"] = curvePriceChecker;
        priceCheckers["AAVE"] = chainlinkPriceChecker;
        priceCheckers["BAT"] = chainlinkPriceChecker;
        priceCheckers["YFI"] = chainlinkPriceChecker;
        priceCheckers["USDT"] = chainlinkPriceChecker;
        priceCheckers["UNI"] = univ3PriceChecker;
        priceCheckers["BAL"] = ssbBalWethPriceChecker;
        priceCheckers["WETH"] = ssbBalWethPriceChecker;
        priceCheckers["COW"] = fixedMinOutPriceChecker;
        priceCheckers["ALCX"] = metaPriceChecker;

        priceCheckerDatas["TOKE"] = curveExpectedOutData();
        priceCheckerDatas["USDC"] = dynamicSlippagePriceCheckerData(10, curveExpectedOutData()); // up to $10 lost allowed
        priceCheckerDatas["GUSD"] = dynamicSlippagePriceCheckerData(100, curveExpectedOutData()); // up to $100 lost allowed

        address[] memory aavePriceFeeds = new address[](1);
        aavePriceFeeds[0] = 0x6Df09E975c830ECae5bd4eD9d90f3A95a4f88012;
        bool[] memory aaveReverses = new bool[](1);
        aaveReverses[0] = false;
        priceCheckerDatas["AAVE"] = dynamicSlippagePriceCheckerData(1000,
            chainlinkExpectedOutData(aavePriceFeeds, aaveReverses));

        address[] memory batPriceFeeds = new address[](2);
        batPriceFeeds[0] = 0x0d16d4528239e9ee52fa531af613AcdB23D88c94;
        batPriceFeeds[1] = 0x194a9AaF2e0b67c35915cD01101585A33Fe25CAa;
        bool[] memory batReverses = new bool[](2);
        batReverses[0] = false;
        batReverses[1] = true;
        priceCheckerDatas["BAT"] = dynamicSlippagePriceCheckerData(600,
            chainlinkExpectedOutData(batPriceFeeds, batReverses));

        priceCheckerDatas["WETH"] = dynamicSlippagePriceCheckerData(200, ssbWethExpectedOutData());

        address[] memory uniSwapPath = new address[](4);
        uniSwapPath[0] = tokenAddress["UNI"];
        uniSwapPath[1] = tokenAddress["WETH"];
        uniSwapPath[2] = tokenAddress["USDC"];
        uniSwapPath[3] = tokenAddress["USDT"];
        uint24[] memory uniPoolFees = new uint24[](3);
        uniPoolFees[0] = 30;
        uniPoolFees[1] = 5;
        uniPoolFees[2] = 1;
        priceCheckerDatas["UNI"] = dynamicSlippagePriceCheckerData(500,
            univ3ExpectedOutData(uniSwapPath, uniPoolFees));

        priceCheckerDatas["BAL"] = dynamicSlippagePriceCheckerData(50, ssbWethExpectedOutData());

        address[] memory yfiPriceFeeds = new address[](1);
        yfiPriceFeeds[0] = 0xA027702dbb89fbd58938e4324ac03B58d812b0E1;
        bool[] memory yfiReverses = new bool[](1);
        yfiReverses[0] = false;
        priceCheckerDatas["YFI"] = dynamicSlippagePriceCheckerData(400,
            chainlinkExpectedOutData(yfiPriceFeeds, yfiReverses));

        address[] memory usdtPriceFeeds = new address[](2);
        usdtPriceFeeds[0] = 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46;
        usdtPriceFeeds[1] = 0xD6aA3D25116d8dA79Ea0246c4826EB951872e02e;
        bool[] memory usdtReverses = new bool[](2);
        usdtReverses[0] = false;
        usdtReverses[1] = true;
        priceCheckerDatas["USDT"] = dynamicSlippagePriceCheckerData(1000,
            chainlinkExpectedOutData(usdtPriceFeeds, usdtReverses));

        priceCheckerDatas["COW"] = fixedMinOutPriceCheckerData(100_000 * 1e18);

        bytes[] memory expectedOutDatas = new bytes[](2);

        address[] memory alcxPriceFeeds = new address[](1);
        alcxPriceFeeds[0] = 0x194a9AaF2e0b67c35915cD01101585A33Fe25CAa;
        bool[] memory alcxReverses = new bool[](1);
        alcxReverses[0] = false;
        expectedOutDatas[0] = chainlinkExpectedOutData(alcxPriceFeeds, alcxReverses);
        expectedOutDatas[1] = univ2ExpectedOutData();

        address[] memory alcxSwapPath = new address[](3);
        alcxSwapPath[0] = tokenAddress["ALCX"];
        alcxSwapPath[1] = tokenAddress["WETH"];
        alcxSwapPath[2] = tokenAddress["TOKE"];

        address[] memory alcxExpectedOutCalculators = new address[](2);
        alcxExpectedOutCalculators[0] = chainlinkExpectedOutCalculator;
        alcxExpectedOutCalculators[1] = sushiswapExpectedOutCalculator;

        priceCheckerDatas["ALCX"] = dynamicSlippagePriceCheckerData(600,
            metaExpectedOutData(alcxSwapPath, alcxExpectedOutCalculators, expectedOutDatas)
        );
    }

    function testRequestSwapExactTokensForTokenTOKE() external {
        requestSwapExactTokensForToken("TOKE");
    }

    function testRequestSwapExactTokensForTokenGUSD() external {
        requestSwapExactTokensForToken("GUSD");
    }

    function testRequestSwapExactTokensForTokenUSDC() external {
        requestSwapExactTokensForToken("USDC");
    }

    function testRequestSwapExactTokensForTokenAAVE() external {
        requestSwapExactTokensForToken("AAVE");
    }

    function testRequestSwapExactTokensForTokenBAT() external {
        requestSwapExactTokensForToken("BAT");
    }

    function testRequestSwapExactTokensForTokenWETH() external {
        requestSwapExactTokensForToken("WETH");
    }

    function testRequestSwapExactTokensForTokenUNI() external {
        requestSwapExactTokensForToken("UNI");
    }

    function testRequestSwapExactTokensForTokenBAL() external {
        requestSwapExactTokensForToken("BAL");
    }

    function testRequestSwapExactTokensForTokenYFI() external {
        requestSwapExactTokensForToken("YFI");
    }

    function testRequestSwapExactTokensForTokenUSDT() external {
        requestSwapExactTokensForToken("USDT");
    }

    function testRequestSwapExactTokensForTokenCOW() external {
        requestSwapExactTokensForToken("COW");
    }

    function testRequestSwapExactTokensForTokenALCX() external {
        requestSwapExactTokensForToken("ALCX");
    }

    function requestSwapExactTokensForToken(string memory tokenToSell) internal {
        {
            string memory tokenToBuy = sellToBuyMap[tokenToSell];
            fromToken = IERC20(tokenAddress[tokenToSell]);
            toToken = IERC20(tokenAddress[tokenToBuy]);
            uint8 decimals = IERC20Metadata(address(fromToken)).decimals();
            amountIn = amounts[tokenToSell] * (10 ** decimals);
            whale = whaleAddresses[tokenToSell];
            priceChecker = priceCheckers[tokenToSell];
            priceCheckerData = priceCheckerDatas[tokenToSell];
        }

        vm.startPrank(whale);
        fromToken.safeApprove(address(milkman), amountIn);
        vm.stopPrank();

        vm.recordLogs();

        vm.prank(whale);
        milkman.requestSwapExactTokensForTokens(
            amountIn,
            fromToken,
            toToken,
            address(this), // Receiver address
            APP_DATA,
            priceChecker,
            priceCheckerData
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        address orderContract = address(0);
        for (uint8 i = 0; i < entries.length; ++i) {
            if (entries[i].topics[0] == SWAP_REQUESTED_EVENT) {
                (orderContract,,,,,,,,) =
                    (abi.decode(entries[i].data, (address, address, uint256, address, address, address, bytes32, address, bytes)));
            }
        }
        assertNotEq(orderContract, address(0));

        assertEq(fromToken.balanceOf(orderContract), amountIn);

        {
            bytes32 expectedSwapHash =
                keccak256(abi.encode(whale, address(this), fromToken, toToken, amountIn, APP_DATA, priceChecker, priceCheckerData));
            assertEq(Milkman(orderContract).swapHash(), expectedSwapHash);
        }

        uint256 buyAmount = 0;
        uint256 feeAmount = 0;
        {
            string[] memory headers = new string[](1);
            headers[0] = "Content-Type: application/json";

            (uint256 status, bytes memory data) = "https://api.cow.fi/mainnet/api/v1/quote".post(
                headers,
                string(
                    abi.encodePacked(
                        '{"sellToken": "',
                        vm.toString(address(fromToken)),
                        '", "buyToken": "',
                        vm.toString(address(toToken)),
                        '", "from": "',
                        vm.toString(whale),
                        '", "kind": "sell", "sellAmountBeforeFee": "',
                        vm.toString(amountIn),
                        '", "priceQuality": "fast", "signingScheme": "eip1271", "verificationGasLimit": 30000',
                        "}"
                    )
                )
            );

            assertEq(status, 200);

            string memory json = string(data);

            buyAmount = parseUint(json, ".quote.buyAmount");
            feeAmount = parseUint(json, ".quote.feeAmount");
        }

        uint256 amountToSell = amountIn - feeAmount;
        assertLt(amountToSell, amountIn);

        assertTrue(
            IPriceChecker(priceChecker).checkPrice(
                amountIn, address(fromToken), address(toToken), feeAmount, buyAmount, priceCheckerData
            )
        );

        uint32 validTo = uint32(block.timestamp) + 60 * 60 * 24;

        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: CoWIERC20(address(fromToken)),
            buyToken: CoWIERC20(address(toToken)),
            receiver: address(this),
            sellAmount: amountToSell,
            feeAmount: feeAmount,
            buyAmount: buyAmount,
            partiallyFillable: false,
            kind: GPv2Order.KIND_SELL,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20,
            validTo: validTo,
            appData: APP_DATA
        });

        bytes memory signatureEncodedOrder = abi.encode(order, whale, priceChecker, priceCheckerData);

        bytes32 orderDigest = order.hash(milkman.DOMAIN_SEPARATOR());

        {
            uint256 gasBefore = gasleft();
            bytes4 isValidSignature = Milkman(orderContract).isValidSignature(orderDigest, signatureEncodedOrder);
            uint256 gasAfter = gasleft();

            uint256 gasConsumed = gasBefore.sub(gasAfter);

            console.log("gas consumed:", gasConsumed);

            assertLt(gasConsumed, 1_000_000);

            assertEq(isValidSignature, MAGIC_VALUE);
        }

        // check that price checker returns false with bad price

        uint256 badAmountOut = buyAmount / 10;

        assertFalse(
            IPriceChecker(priceChecker).checkPrice(
                amountToSell, address(fromToken), address(toToken), feeAmount, badAmountOut, priceCheckerData
            )
        );

        // check that milkman reverts with bad price

        order.buyAmount = badAmountOut;
        signatureEncodedOrder = abi.encode(order, whale, priceChecker, priceCheckerData);
        orderDigest = order.hash(milkman.DOMAIN_SEPARATOR());
        vm.expectRevert("invalid_min_out");
        Milkman(orderContract).isValidSignature(orderDigest, signatureEncodedOrder);
        order.buyAmount = buyAmount;

        // check that milkman reverts if the hash doesn't match the order

        orderDigest = order.hash(milkman.DOMAIN_SEPARATOR());
        order.validTo = validTo + 10;
        signatureEncodedOrder = abi.encode(order, whale, priceChecker, priceCheckerData);
        vm.expectRevert("!match");
        Milkman(orderContract).isValidSignature(orderDigest, signatureEncodedOrder);
        order.validTo = validTo;

        // check that milkman reverts if the keeper generates a buy order

        order.kind = GPv2Order.KIND_BUY;
        orderDigest = order.hash(milkman.DOMAIN_SEPARATOR());
        signatureEncodedOrder = abi.encode(order, whale, priceChecker, priceCheckerData);
        vm.expectRevert("!kind_sell");
        Milkman(orderContract).isValidSignature(orderDigest, signatureEncodedOrder);
        order.kind = GPv2Order.KIND_SELL;

        // check that milkman reverts if the validTo is too close

        uint32 badValidTo = uint32(block.timestamp) + 2 * 60;
        order.validTo = badValidTo;
        orderDigest = order.hash(milkman.DOMAIN_SEPARATOR());
        signatureEncodedOrder = abi.encode(order, whale, priceChecker, priceCheckerData);
        vm.expectRevert("expires_too_soon");
        Milkman(orderContract).isValidSignature(orderDigest, signatureEncodedOrder);
        order.validTo = validTo;

        // check that milkman reverts for non-fill-or-kill orders

        order.partiallyFillable = true;
        orderDigest = order.hash(milkman.DOMAIN_SEPARATOR());
        signatureEncodedOrder = abi.encode(order, whale, priceChecker, priceCheckerData);
        vm.expectRevert("!fill_or_kill");
        Milkman(orderContract).isValidSignature(orderDigest, signatureEncodedOrder);
        order.partiallyFillable = false;

        // check that milkman reverts if set to non ERC20 sell balance

        order.sellTokenBalance = GPv2Order.BALANCE_EXTERNAL;
        orderDigest = order.hash(milkman.DOMAIN_SEPARATOR());
        signatureEncodedOrder = abi.encode(order, whale, priceChecker, priceCheckerData);
        vm.expectRevert("!sell_erc20");
        Milkman(orderContract).isValidSignature(orderDigest, signatureEncodedOrder);
        order.sellTokenBalance = GPv2Order.BALANCE_ERC20;

        // check that milkman reverts if set to non ERC20 buy balance

        order.buyTokenBalance = GPv2Order.BALANCE_INTERNAL;
        orderDigest = order.hash(milkman.DOMAIN_SEPARATOR());
        signatureEncodedOrder = abi.encode(order, whale, priceChecker, priceCheckerData);
        vm.expectRevert("!buy_erc20");
        Milkman(orderContract).isValidSignature(orderDigest, signatureEncodedOrder);
        order.buyTokenBalance = GPv2Order.BALANCE_ERC20;
    }
}
