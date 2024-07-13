// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {Hooks} from "../lib/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../lib/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "../lib/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../lib/v4-core/src/types/BeforeSwapDelta.sol";
import {BaseClass} from "./BaseClass.sol";

contract Slippage is BaseClass {
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

    function _calcLiquidityCoef() internal returns (uint256) {
        return uint256(1e18);
    }

    function _beforeSwap(
        address usr,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        super._beforeSwap(usr, key, params, data);
        uint256 liquidityCoef = _calcLiquidityCoef();
        uint256 specifiedDelta = params.amountSpecified * liquidityCoef
        uint256 unspecifiedDelta =
        uint256 BeforeSwapDelta = toBeforeSwapDelta(specifiedDelta, 0);
        params.amountSpecified = params.amountSpecified * liquidityCoef;
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
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

        totalLiquidity += params.liquidityDelta.toInt128();

        return BaseHook.beforeAddLiquidity.selector;
    }

    function _afterRemoveLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata data
    ) internal virtual returns (bytes4, BalanceDelta) {
        super._afterRemoveLiquidity(usr, key, params, data);

        totalLiquidity += params.liquidityDelta.toInt128();

        BalanceDelta delta = BalanceDelta.wrap(params);

        int256 amount0 = delta.amount0() +
            userDelta[usr].amount0 -
            globalDelta.amount0;
        int256 amount1 = delta.amount1() +
            userDelta[usr].amount1 -
            globalDelta.amount1;

        return BaseHook.beforeRemoveLiquidity.selector;
    }
}
