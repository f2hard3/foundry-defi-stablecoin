// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// Have our invariant aka properties
// What are our invariants?
// 1. The total supply of DS should be less than the total value of collateral
// 2. Getter view functions should never revert

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDS} from "../../script/DeployDS.s.sol";
import {DSEngine} from "../../src/DSEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant {
    DecentralizedStablecoin private ds;
    DSEngine private dsEngine;
    Handler private handler;
    HelperConfig private config;
    address private weth;
    address private wbtc;

    function setUp() external {
        DeployDS deployer = new DeployDS();
        (ds, dsEngine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dsEngine, ds);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = ds.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsEngine));

        uint256 wethValue = dsEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("wethValue:", wethValue);
        console.log("wbtcValue:", wbtcValue);
        console.log("totalSupply:", totalSupply);
        console.log("times mint called:", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
