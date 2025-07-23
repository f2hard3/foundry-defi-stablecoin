// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {DSEngine} from "../src/DSEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDS is Script {
    address[] private tokenAddresses;
    address[] private priceFeedAddresses;

    function run() external returns (DecentralizedStablecoin, DSEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizedStablecoin ds = new DecentralizedStablecoin(vm.addr(deployerKey));
        DSEngine engine = new DSEngine(tokenAddresses, priceFeedAddresses, address(ds));
        ds.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (ds, engine, config);
    }
}
