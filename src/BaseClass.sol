// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

abstract contract BaseClass is BaseHook {
    /**
     * INTERNALS - Your logic comes here *********************
     */
    function _beforeSwap(
        address usr,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    ) internal virtual returns (bytes4, BeforeSwapDelta, uint24) {}

    function _afterSwap(
        address usr,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) internal virtual returns (bytes4, int128) {}

    function _afterAddLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        bytes calldata data
    ) internal virtual returns (bytes4, BalanceDelta) {}

    function _beforeAddLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata data
    ) internal virtual returns (bytes4) {}

    function _beforeRemoveLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata data
    ) internal virtual returns (bytes4) {}

    function _afterRemoveLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) internal virtual returns (bytes4, BalanceDelta) {}

    /**
     * INTERFACES - DO NOT CHANGE *********************
     */
    function beforeSwap(
        address usr,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        return _beforeSwap(usr, key, params, data);
    }

    function afterSwap(
        address usr,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) external override returns (bytes4, int128) {
        return _afterSwap(usr, key, params, delta, data);
    }

    function beforeAddLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata data
    ) external override returns (bytes4) {
        return _beforeAddLiquidity(usr, key, params, data);
    }
    function afterAddLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata parm,
        BalanceDelta delta,
        bytes calldata data
    ) external override returns (bytes4, BalanceDelta) {
        return _afterAddLiquidity(usr, key, parm, delta, data);
    }

    function beforeRemoveLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata data
    ) external override returns (bytes4) {
        return _beforeRemoveLiquidity(usr, key, params, data);
    }

    function afterRemoveLiquidity(
        address usr,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) external override returns (bytes4, BalanceDelta) {
        return _afterRemoveLiquidity(usr, key, params, delta, data);
    }
}
