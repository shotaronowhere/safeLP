// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {Hooks} from "../lib/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../lib/v4-core/src/types/PoolId.sol";
import {toBalanceDelta, BalanceDelta, BalanceDeltaLibrary} from "../lib/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta, BeforeSwapDeltaLibrary} from "../lib/v4-core/src/types/BeforeSwapDelta.sol";
import {BaseClass} from "./BaseClass.sol";

int256 constant PRECISION = 1e18;
int24 constant MIN_TICK = -887220;
int24 constant MAX_TICK = -MIN_TICK;

struct DeltaTokens {
    int256 token0;
    int256 token1;
}

contract Slippage is BaseClass {
    using BalanceDeltaLibrary for BalanceDelta;
    uint256 startBlock;
    uint256 endBlock;
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        startBlock = 1000;
        endBlock = 2000;
    }

    // delta
    DeltaTokens public globalDelta;
    mapping(address => DeltaTokens) userDelta;

    // liquidity
    mapping(address => int256) userLiquidity;
    int256 totalLiquidity;

    function getHookPermissions()
        public
        pure
        virtual
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: true,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // trading operations

    function _calcLiquidityCoef(int256 price) internal view returns (int256) {
        int256 currentBlock = int256(block.timestamp);
        int256 marketDuration = int256(endBlock) - int256(startBlock);
        int256 percentComplete = ((currentBlock - int256(startBlock)) * 1e18) /
            marketDuration;
        int256 initialPrice = 5e17; // 0.5 in 18 decimal fixed-point

        // Calculate time-based decay
        int256 timeDecay = (9e17 * (1e18 - percentComplete)) / 1e18 + 1e17;

        // Calculate price-based decay
        int256 priceDistance = abs(price - initialPrice);
        int256 priceDecay = (9e17 * (5e17 - priceDistance)) / 5e17 + 1e17;

        // Combine decays (multiplicative)
        return (timeDecay * priceDecay) / 1e18;
    }

    // Helper function to calculate absolute value
    function abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }

    function _beforeSwap(
        address usr,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        super._beforeSwap(usr, key, params, data);
        int256 price = 5e17;
        int256 liquidityCoef = _calcLiquidityCoef(price);
        int256 specifiedDelta = params.amountSpecified * liquidityCoef;
        BeforeSwapDelta beforeSwapDelta = toBeforeSwapDelta(
            int128(specifiedDelta),
            0
        );

        int256 scaledFee = int256(uint256(key.fee)) / liquidityCoef;

        return (
            BaseHook.beforeSwap.selector,
            beforeSwapDelta,
            uint24(uint256(scaledFee))
        );
    }

    function _afterSwap(
        address usr,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) internal virtual override returns (bytes4, int128) {
        super._afterSwap(usr, key, params, delta, data);
        int256 amount0 = delta.amount0();
        int256 amount1 = delta.amount1();

        (int256 amount0Deflated, int256 amount1Deflated) = _deflateAmounts(
            delta.amount0(),
            delta.amount1()
        );
        int256 amount0Delta = amount0 - amount0Deflated;
        int256 amount1Delta = amount1 - amount1Deflated;

        poolManager.settle(outbound);

        return (BaseHook.afterSwap.selector, int128(amount1Delta));
    }

    function _deflateAmounts(
        int256 amount0,
        int256 amount1
    ) internal pure returns (int256, int256) {
        int256 price = 5e17;
        int256 liquidityCoef = _calcLiquidityCoef(price);

        int256 amount0Deflated = (amount0 * liquidityCoef) / PRECISION;
        int256 amount1Deflated = (amount1 * liquidityCoef) / PRECISION;

        int256 amount0Delta = amount0 - amount0Deflated;
        int256 amount1Delta = amount1 - amount1Deflated;

        int256 newDelta = BalanceDelta.unwrap(
            toBalanceDelta(int128(amount0), int128(amount1))
        );

        return (BaseHook.afterSwap.selector, int128(newDelta));
        return (amount0Deflated, amount1Deflated);
    }

    // Liquidity Operations
    function _beforeAddLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata data
    ) internal virtual override returns (bytes4) {
        super._beforeAddLiquidity(usr, key, params, data);
        require(userLiquidity[usr] == 0, "no more liquidity");
        require(
            params.tickLower == MIN_TICK && params.tickUpper == MAX_TICK,
            "No ticks"
        );

        // up liquidity
        userDelta[usr] = globalDelta;
        totalLiquidity += params.liquidityDelta;

        return BaseHook.beforeAddLiquidity.selector;
    }

    function _afterRemoveLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) internal virtual override returns (bytes4, BalanceDelta) {
        super._afterRemoveLiquidity(usr, key, params, delta, data);

        // cache liquidity
        int256 liquidityRemoved = userLiquidity[usr];
        require(params.liquidityDelta == liquidityRemoved, "Can not remove");

        // remove token amounts
        int256 amount0 = int256(delta.amount0()) +
            ((userDelta[usr].token0 - globalDelta.token0) *
                params.liquidityDelta) /
            PRECISION;
        int256 amount1 = int256(delta.amount1()) +
            ((userDelta[usr].token1 - globalDelta.token1) *
                params.liquidityDelta) /
            PRECISION;
        BalanceDelta newDelta = toBalanceDelta(
            int128(amount0),
            int128(amount1)
        );

        // up liquidity
        totalLiquidity += params.liquidityDelta;
        delete userDelta[usr];

        return (BaseHook.beforeRemoveLiquidity.selector, newDelta);
    }
}
