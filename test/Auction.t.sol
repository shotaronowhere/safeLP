// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../lib/forge-std/src/Test.sol";
import {IHooks} from "../lib/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "../lib/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "../lib/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "../lib/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "../lib/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "../lib/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "../lib/v4-core/src/test/PoolSwapTest.sol";
import {Deployers} from "../lib/v4-core/test/utils/Deployers.sol";
import {StateLibrary} from "../lib/v4-core/src/libraries/StateLibrary.sol";

import "../src/Auction.sol";

contract AuctionTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    AuctionHook hook;
    PoolId poolId;

    uint256 endTime = block.timestamp + 15 minutes;
    bool isZeroUnderlying = true;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG) ^
                (0x4444 << 145) // Namespace the hook to avoid collisions
        );
        deployCodeTo("Auction.sol:AuctionHook", abi.encode(manager, isZeroUnderlying), flags);
        hook = AuctionHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Provide full-range liquidity to the pool
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(60),
                TickMath.maxUsableTick(60),
                10_000 ether,
                0
            ),
            ZERO_BYTES
        );
    }

    function testAuctionHooks() public {
        assertEq(hook.isZeroUnderlying(), isZeroUnderlying, "Wrong isZeroUnderlying");
    }

    function testTrading() public {
        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!

        // trading before end time
        BalanceDelta swapDelta = swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );

        (,,,,,,uint64 expiry,) = hook.auctions(0);
        assertEq(expiry, block.timestamp + hook.TIMEOUT());
    }
}
