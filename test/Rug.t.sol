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

import "../src/Rug.sol";

contract RugTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Rug hook;
    PoolId poolId;

    uint256 endTime = block.timestamp + 15 minutes;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG) ^
                (0x4444 << 145) // Namespace the hook to avoid collisions
        );
        deployCodeTo("Rug.sol:Rug", abi.encode(manager, endTime), flags);
        hook = Rug(flags);

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

    function testRugHooks() public {
        assertEq(hook.endTime(), endTime, "Wrong endtime");
    }

    function testNoTrading() public {
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

        // trading after end time
        vm.warp(endTime);
        vm.expectRevert(Rug.TimeExpired.selector);
        swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );
    }
}
