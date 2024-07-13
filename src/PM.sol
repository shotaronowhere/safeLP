// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import {BaseHook} from "v4-periphery/BaseHook.sol"; 
// import {BaseClass} from "./BaseClass.sol";
// import {Rug} from "./Rug.sol";
// import {Slippage} from "./Slippage.sol";
// import {Hooks} from "../lib/v4-core/src/libraries/Hooks.sol";
// import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";

// contract PM is Rug, Slippage {

//     constructor(IPoolManager _poolManager, uint256 _endTime) Slippage(_poolManager) Rug(_poolManager,   _endTime)  {
//     }

//     function getHookPermissions()
//         public
//         pure
//         override(Rug, Slippage)
//         returns (Hooks.Permissions memory)
//     {
//         return
//             Hooks.Permissions({
//                 beforeInitialize: false,
//                 afterInitialize: false,
//                 beforeAddLiquidity: true,
//                 afterAddLiquidity: false,
//                 beforeRemoveLiquidity: false,
//                 afterRemoveLiquidity: false,
//                 beforeSwap: true,
//                 afterSwap: false,
//                 beforeDonate: false,
//                 afterDonate: false,
//                 beforeSwapReturnDelta: false,
//                 afterSwapReturnDelta: false,
//                 afterAddLiquidityReturnDelta: false,
//                 afterRemoveLiquidityReturnDelta: false
//             });
//     }

// }
