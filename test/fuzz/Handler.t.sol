// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DSEngine} from "../../src/DSEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

// Handler is going to narrow down the way we call function
contract Handler is Test {
    DSEngine private dsEngine;
    DecentralizedStablecoin private ds;
    ERC20Mock private weth;
    ERC20Mock private wbtc;
    MockV3Aggregator private ethUsdPriceFeed;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;

    uint256 private constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSEngine _dsEngine, DecentralizedStablecoin _ds) {
        dsEngine = _dsEngine;
        ds = _ds;

        address[] memory collateralTokens = dsEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsEngine.getCollateralPriceFeed(address(weth)));
    }

    // redeem collateral
    function depositCollateral(uint256 tokenCollateralSeed, uint256 amountCollateral) external {
        ERC20Mock tokenCollateral = _getCollateralFromSeed(tokenCollateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        tokenCollateral.mint(msg.sender, amountCollateral);
        tokenCollateral.approve(address(dsEngine), amountCollateral);
        dsEngine.depositCollateral(address(tokenCollateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 tokenCollateralSeed, uint256 amountCollateral) external {
        ERC20Mock tokenCollateral = _getCollateralFromSeed(tokenCollateralSeed);
        uint256 currentCollateralBalance = dsEngine.getCollateralBalanceOfUser(msg.sender, address(tokenCollateral));
        amountCollateral = bound(amountCollateral, 0, currentCollateralBalance);
        if (amountCollateral == 0) {
            return; // Skip if nothing to redeem
        }
        vm.startPrank(msg.sender);
        dsEngine.redeemCollateral(address(tokenCollateral), amountCollateral);
        vm.stopPrank();
    }

    function mintDs(uint256 amountDsToMint, uint256 addressSeed) external {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDsMinted, uint256 collateralValueInUsd) = dsEngine.getAccountInformation(sender);
        uint256 maxDsToMint = (collateralValueInUsd / 2) - totalDsMinted;
        if (maxDsToMint < 0) {
            return;
        }
        amountDsToMint = bound(amountDsToMint, 0, maxDsToMint);
        if (amountDsToMint == 0) {
            return;
        }
        vm.startPrank(sender);
        dsEngine.mintDs(amountDsToMint);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    // This might break our invariant test suite.
    // function updateCollateralPrice(uint96 newPrice) external {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function _getCollateralFromSeed(uint256 tokenCollateralSeed) private view returns (ERC20Mock) {
        if (tokenCollateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
