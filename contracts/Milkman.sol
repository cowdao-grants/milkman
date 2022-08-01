// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {GPv2Order} from "@cow-protocol/contracts/libraries/GPv2Order.sol";

import {IGPv2Settlement} from "../interfaces/IGPv2Settlement.sol";
import {IPriceChecker} from "../interfaces/IPriceChecker.sol";

contract Milkman {
    using SafeERC20 for IERC20;
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    event SwapRequested(
        bytes32 swapID,
        address user,
        address receiver,
        IERC20 fromToken,
        IERC20 toToken,
        uint256 amountIn,
        address priceChecker,
        uint256 nonce
    );
    // swapID is generated by Milkman, orderUID is generated by CoW Protocol
    event SwapPaired(bytes32 swapID, bytes orderUID, uint256 blockNumber);
    event SwapUnpaired(bytes32 swapID);
    event SwapExecuted(bytes32 swapID);

    // global nonce that is incremented after every swap request
    uint256 public nonce = 0;
    // map swap ID => empty if not active, bytes(1) if requested but not paired, and packed blockNumber,orderUID if paired
    mapping(bytes32 => bytes) public swaps;

    // Who we give allowance
    address internal constant gnosisVaultRelayer =
        0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    // Where we pre-sign
    IGPv2Settlement internal constant settlement =
        IGPv2Settlement(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);
    // Settlement's domain separator, used to hash order IDs
    bytes32 internal constant domainSeparator =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;

    bytes32 internal constant KIND_SELL =
        hex"f3b277728b3fee749481eb3e0b3b48980dbbab78658fc419025cb16eee346775";

    uint32 internal constant FIVE_MINUTES_IN_SECONDS = 300;

    // Request to asynchronously swap exact tokens for market value of other tokens through CoW Protocol
    function requestSwapExactTokensForTokens(
        uint256 _amountIn,
        IERC20 _fromToken,
        IERC20 _toToken,
        address _to,
        address _priceChecker // used to verify that any UIDs passed in are setting reasonable minOuts. Set to address 0 if you don't want.
    ) external {
        _fromToken.transferFrom(msg.sender, address(this), _amountIn);

        // Assumption: relayer allowance always either 0 or so high that it will never need to be set again
        if (_fromToken.allowance(address(this), gnosisVaultRelayer) == 0) {
            _fromToken.safeApprove(gnosisVaultRelayer, type(uint256).max);
        }

        uint256 _nonce = nonce;
        nonce += 1;

        bytes32 _swapID = keccak256(
            abi.encode(
                msg.sender,
                _to,
                _fromToken,
                _toToken,
                _amountIn,
                _priceChecker,
                _nonce
            )
        );

        swaps[_swapID] = abi.encode(1);

        emit SwapRequested(
            _swapID,
            msg.sender,
            _to,
            _fromToken,
            _toToken,
            _amountIn,
            _priceChecker,
            _nonce
        );
    }

    // Called by a bot who has generated a UID via the API
    function pairSwap(
        bytes calldata _orderUid,
        GPv2Order.Data calldata _order,
        address _user,
        address _priceChecker,
        uint256 _nonce
    ) external {
        bytes32 _orderDigestFromOrderDetails = _order.hash(domainSeparator);
        (bytes32 _orderDigestFromUid, address _owner, ) = _orderUid
            .extractOrderUidParams();

        require(address(this) == _owner, "owner!=milkman");

        require(_orderDigestFromOrderDetails == _orderDigestFromUid, "!match");

        bytes32 _swapID = keccak256(
            abi.encode(
                _user,
                _order.receiver,
                _order.sellToken,
                _order.buyToken,
                _order.sellAmount + _order.feeAmount,
                _priceChecker,
                _nonce
            )
        );

        bytes memory _swapData = swaps[_swapID];
        require(
            _swapData.length == 32 && _swapData[31] == bytes1(uint8(1)),
            "!swap_requested"
        );

        require(_order.kind == KIND_SELL, "!kind_sell");

        require(
            _order.validTo >= block.timestamp + FIVE_MINUTES_IN_SECONDS,
            "expires_too_soon"
        );

        require(!_order.partiallyFillable, "!fill_or_kill");

        swaps[_swapID] = abi.encode(block.number, _orderUid);

        if (_priceChecker != address(0)) {
            require(
                IPriceChecker(_priceChecker).checkPrice(
                    _order.sellAmount + _order.feeAmount,
                    address(_order.sellToken),
                    address(_order.buyToken),
                    _order.buyAmount
                ),
                "invalid_min_out"
            );
        }

        settlement.setPreSignature(_orderUid, true);

        emit SwapPaired(_swapID, _orderUid, block.number);
    }

    // prove that a paired swap hasn't been executed in 50 blocks
    function unpairSwap(bytes32 _swapID) external {
        (uint256 _blockNumberWhenPaired, bytes memory _orderUid) = abi.decode(
            swaps[_swapID],
            (uint256, bytes)
        );

        require(
            block.number >= _blockNumberWhenPaired + 50 &&
                settlement.filledAmount(_orderUid) == 0 &&
                _blockNumberWhenPaired != 0, // last check to ensure that the swap exists at all
            "!unpairable"
        );

        settlement.setPreSignature(_orderUid, false);

        swaps[_swapID] = abi.encode(1);

        emit SwapUnpaired(_swapID);
    }

    // prove that a paired swap has been exec'ed by the CoW protocol
    function proveExecuted(bytes32 _swapID) external {
        (, bytes memory _orderUid) = abi.decode(
            swaps[_swapID],
            (uint256, bytes)
        );

        require(settlement.filledAmount(_orderUid) != 0, "!executed");

        delete swaps[_swapID];

        emit SwapExecuted(_swapID);
    }
}