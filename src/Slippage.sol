// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {Hooks} from "../lib/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../lib/v4-core/src/types/PoolId.sol";
import {toBalanceDelta, BalanceDelta, BalanceDeltaLibrary} from "../lib/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../lib/v4-core/src/types/BeforeSwapDelta.sol";
import {BaseClass} from "./BaseClass.sol";

int256 constant PRECISION = 1e18;

contract Slippage is BaseClass {
    using BalanceDeltaLibrary for BalanceDelta;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    struct DeltaTokens {
        int256 token0;
        int256 token1;
    }

    DeltaTokens public globalDelta;
    mapping(address => DeltaTokens) userDelta;

    int256 totalLiquidity;

    function getHookPermissions()
        public
        pure
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

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function _calcLiquidityCoef(int256 price) internal returns (int256) {
        return 1e18;
    }

    function _beforeSwap(
        address usr,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        super._beforeSwap(usr, key, params, data);
        int256 liquidityCoef = _calcLiquidityCoef();
        int256 specifiedDelta = params.amountSpecified * liquidityCoef;
        int256 beforeSwapDelta = toBeforeSwapDelta(specifiedDelta, 0);
        params.amountSpecified = params.amountSpecified * liquidityCoef;
        int256 scaledFee = key.fee / liquidityCoef;

        return (BaseHook.beforeSwap.selector, beforeSwapDelta, key.fee);
    }

    function _afterSwap(
        address usr,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) internal virtual override returns (bytes4, int128) {
        super._afterSwap(usr, key, params, delta, data);

        return (BaseHook.afterSwap.selector, 0);
    }

    /// @dev Min tick for full range with tick spacing of 60
    int24 internal constant MIN_TICK = -887220;
    /// @dev Max tick for full range with tick spacing of 60
    int24 internal constant MAX_TICK = -MIN_TICK;

    function _beforeAddLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata data
    ) internal virtual override returns (bytes4) {
        super._beforeAddLiquidity(usr, key, params, data);
        require(
            params.tickLower == MIN_TICK && params.tickUpper == MAX_TICK,
            "No ticks"
        );

        userDelta[usr] = globalDelta;

        totalLiquidity += params.liquidityDelta;

        return BaseHook.beforeAddLiquidity.selector;
    }

    function _afterRemoveLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata data
    ) internal virtual override returns (bytes4, BalanceDelta) {
        super._afterRemoveLiquidity(usr, key, params, data);

        totalLiquidity += params.liquidityDelta;

        bytes memory parameter = abi.encode(params);

        BalanceDelta delta = abi.decode(parameter, (BalanceDelta));

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
        return (BaseHook.beforeRemoveLiquidity.selector, newDelta);
    }
}
