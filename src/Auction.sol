// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "../lib/v4-periphery/contracts/BaseHook.sol"; 
import {Hooks} from "../lib/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../lib/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "../lib/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "../lib/v4-core/src/types/Currency.sol";
import {IHooks} from "../lib/v4-core/src/interfaces/IHooks.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../lib/v4-core/src/types/BeforeSwapDelta.sol";
import {IERC20} from "../lib/v4-periphery/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/*
*   @title AuctionCreator
*   @notice This AuctionCreator hook protects LPs in prediction market pools where 
*   outcome tokens are traded for underlying tokens.
*   eg. Who will win 2024 US Presidential Election, Trump or Biden? 
*   The market over this question is created by minting $TRUMP and $BIDEN against $DAI.
*   The market will trade in the $TRUMP/$DAI and $BIDEN/$DAI pools
*/
contract AuctionHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    struct Auction {
        uint128 outcomeAmount;
        uint128 underlyingAmount;
        uint128 underlyingAmountOriginal;
        Currency outcomeToken;
        Currency underlyingToken;
        address winner;
        uint64 expiry;
        bool isAscending;
    }

    event AuctionBid(uint256 id, Auction auction);
    
    bool public immutable isZeroUnderlying; // true if currency0 is the underlying collateral eg $DAI $ETH

    uint256 public constant TIMEOUT = 60 * 60; // 1 hour
    uint256 public constant MIN_BID_IN_BASIS = 100; // 1%
    uint256 public constant BASIS = 10000;

    uint256 public count;
    address public owner;
    mapping(uint256 => Auction) public auctions; 

    constructor(IPoolManager _poolManager, bool _isZeroUnderlying) BaseHook(_poolManager) {
        isZeroUnderlying = _isZeroUnderlying;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // @inheritdoc IHooks
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4, BeforeSwapDelta, uint24){
        // afterSwap hook must take the output token (since we auction the output)
        // since it's best practice to manage the afterSwap delat with the unspecified currency
        // we hence require the input to be specified
        require(params.amountSpecified < 0, "Invalid swap");
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }


    /// @notice The hook called after a swap
    /// @param sender The initial msg.sender for the swap call
    /// @param key The key for the pool
    /// @param params The parameters for the swap
    /// @param delta The amount owed to the caller (positive) or owed to the pool (negative)
    /// @param hookData Arbitrary data handed into the PoolManager by the swapper to be be passed on to the hook
    /// @return bytes4 The function selector for the hook
    /// @return int128 The hook's delta in unspecified currency. Positive: the hook is owed/took currency, negative: the hook owes/sent currency
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {

        createAuction(sender, key, params, delta);

        (Currency currencyUnspecified, int128 amountUnspecified) =
            (params.zeroForOne) ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());

        poolManager.take(currencyUnspecified, address(this), uint256(uint128(amountUnspecified)));

        return (BaseHook.afterSwap.selector, amountUnspecified);
    }

    // pre-condition aprove allowance
    function bid(uint256 id, uint128 amount) external {
        Auction memory auction = auctions[id];

        //check
        require(!isExpired(auction.expiry), "auction expired");
        bool isEnough;
        if (auction.isAscending){
            isEnough = amount > auction.underlyingAmount;
        } else {
            isEnough = amount < auction.underlyingAmount; 
        }
        require(isEnough, "not enough");

        IERC20 bidToken = IERC20(Currency.unwrap(auction.underlyingToken));
        uint256 oldBidAmount = auction.underlyingAmount;
        address oldWinner = auction.winner;

        auction.winner = msg.sender;
        auction.underlyingAmount = amount;
        auction.expiry = expirationTime();

        // effects
        auctions[id] = auction;

        // interactions
        // refund previous winner
        bidToken.transfer(oldWinner, oldBidAmount);
        bidToken.transferFrom(oldWinner, address(this), amount);
    }

    function claim(uint256 id) external {
        Auction memory auction = auctions[id];

        //check
        require(isExpired(auction.expiry), "auction not expired");

        //effects
        delete auctions[id];

        Currency winningCurrency = auction.isAscending ? auction.underlyingToken : auction.outcomeToken;
        IERC20 winningToken = IERC20(Currency.unwrap(winningCurrency));
        uint256 proceeds = auction.isAscending ? 
            auction.underlyingAmount - auction.underlyingAmountOriginal :
            auction.underlyingAmountOriginal - auction.underlyingAmount;
        winningToken.transfer(auction.winner, auction.underlyingAmount);
        winningToken.transfer(owner, proceeds);
    }


    function createAuction(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta
    ) internal {
        // we auction the unspecified output token of the swap
        // params.zeroForOne direction of the swap true for token0 to token1, false for token1 to token0
        // when when swap the underlying for the outcome, we use ascending auctions, else decending
        bool isAscending = params.zeroForOne && isZeroUnderlying;

        (Currency underlying, int128 underlyingAmount) = isZeroUnderlying ? 
            (key.currency0, delta.amount0()) : 
            (key.currency1, delta.amount1());

        (Currency outcome, int128 outcomeAmount) = isZeroUnderlying ? 
            (key.currency0, delta.amount0()) : 
            (key.currency1, delta.amount1());

        // todo use unique hash for common info in key value mapping
        // eg keccak256(abi.encode(auctionAmount, auctionToken, isAscending, bidToken))
        // mapping to a struct { bidAmount, winner, expiry }

        Auction memory auction = Auction({
            outcomeAmount: outcomeAmount < 0 ? uint128(-outcomeAmount) : uint128(outcomeAmount),
            underlyingAmount: underlyingAmount < 0 ? uint128(-underlyingAmount) : uint128(underlyingAmount),
            underlyingAmountOriginal: underlyingAmount < 0 ? uint128(-underlyingAmount) : uint128(underlyingAmount),
            outcomeToken: outcome,
            underlyingToken: underlying,
            winner: sender,
            isAscending: isAscending,
            expiry: expirationTime()
        });

        uint256 id = count++;

        auctions[id] = auction;
        emit AuctionBid(id, auction);
    }

    function isExpired(uint64 deadline) internal returns (bool) {
        return block.timestamp > deadline;
    }

    function expirationTime() internal returns (uint64) {
        return uint64(block.timestamp + TIMEOUT);
    }

    function winner(uint64 id) external returns (address) {
        Auction memory auction = auctions[id];
        require(auction.expiry != 0, "Auction does not exist");
        require(isExpired(auction.expiry), "Auction is not over");
        return auction.winner;
    } 
}

