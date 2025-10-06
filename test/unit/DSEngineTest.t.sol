// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDS} from "../../script/DeployDS.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {DSEngine} from "../../src/DSEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSEngineTest is Test {
    DecentralizedStablecoin private ds;
    DSEngine private engine;
    HelperConfig private config;
    address private wethUsdPriceFeed;
    address private wbtcUsdPriceFeed;
    address private weth;

    address private immutable i_user = makeAddr("user");
    uint256 private constant AMOUNT_COLLATERAL = 10 ether;
    uint256 private constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() external {
        DeployDS deployer = new DeployDS();
        (ds, engine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(i_user, STARTING_ERC20_BALANCE);
    }

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() external {
        // Arrange
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = weth;
        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = wethUsdPriceFeed;
        priceFeedAddresses[1] = wbtcUsdPriceFeed;

        // Act and Assert
        vm.expectRevert(DSEngine.DSEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSEngine(tokenAddresses, priceFeedAddresses, address(ds));
    }

    function testGetUsdValue() external view {
        // Arrange
        uint256 ethAmount = 15e18;
        // (2000e8 * 1e10 * 15e18) / 1e18
        uint256 expectedUsd = 30_000e18;

        // Act
        uint256 usdValue = engine.getUsdValue(weth, ethAmount);

        // Assert
        assertEq(expectedUsd, usdValue);
    }

    function testGetTokenAmountFromUsd() external view {
        // Arrange
        uint256 usdAmountInWei = 10 * 1e18; // $10
        // ($10e18 * 1e18) / ($2000e8 * 1e10) = 0.005 * 1e18 = 5 * 1e15
        uint256 expectedWeth = 0.005 ether;

        // Act
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmountInWei);

        // Assert
        assertEq(expectedWeth, actualWeth);
    }

    function testRevertsIfCollateralZero() external {
        // Arrange
        vm.startPrank(i_user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        uint256 ethAmountCollateral = 0;

        // Act and Assert
        vm.expectRevert(DSEngine.DSEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, ethAmountCollateral);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() external {
        ERC20Mock unApprovedToken = new ERC20Mock();
        ERC20Mock(unApprovedToken).mint(i_user, AMOUNT_COLLATERAL);
        vm.startPrank(i_user);
        vm.expectRevert(DSEngine.DSEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(unApprovedToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(i_user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() external depositedCollateral {
        // Arrange and Act
        (uint256 totalDsMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(i_user);
        uint256 expectedTotalDsMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        // Assert
        assertEq(totalDsMinted, expectedTotalDsMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }
}
