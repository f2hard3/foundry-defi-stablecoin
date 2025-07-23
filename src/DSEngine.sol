// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStablecoin} from "./DecentralizedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSEngine
 * @author Sunggon Park
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain 1 token = $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Algorithmically Stable
 * - Dollar Pegged
 *
 * Our DS system should always be "overcollateralized". At no point, should the value of all collateral >= the $ backed value of all the DS.
 *
 * @notice This contract is the core of the DS System. It handles all the logic for mining and redeeming DS, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DS (DAI) system.
 */
contract DSEngine is ReentrancyGuard {
    /**
     * Errors
     *
     */
    error DSEngine__NeedsMoreThanZero();
    error DSEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSEngine__NotAllowedToken();
    error DSEngine__TransferFailed();
    error DSEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSEngine__MintFailed();
    error DSEngine__HealthFactorOk();
    error DSEngine__HealthFactorNotImproved();

    /**
     * Types
     *
     */
    using OracleLib for AggregatorV3Interface;

    /**
     * State Variables
     *
     */
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 50% means 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // this means a 10% bonus

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSMinted;
    DecentralizedStablecoin private immutable i_ds;
    address[] private s_collateralTokens;

    /**
     * Events
     *
     */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /**
     *  Modifiers
     *
     */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSEngine__NotAllowedToken();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dsAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_ds = DecentralizedStablecoin(dsAddress);
    }

    /**
     *  External Functions
     *
     */

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDsToMint The amount of decentralized stablecoin to mint
     * @notice this function will deposit your collateral and mint DS in one transaction
     */
    function depositCollateralAndMintDs(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDsToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDs(amountDsToMint);
    }

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @notice this function will burn DS  and redeem underlying collateral in one transaction
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert DSEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress The address of the token of the collateral to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDsToBurn  The amount of decentralized stablecoin to burn
     */
    function redeemCollateralForDs(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDsToBurn)
        external
    {
        burnDs(amountDsToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @notice They must have more collateral value than the minimum threshold
     * @param amountDsToMint The amount of decentralized stablecoin to mint
     */
    function mintDs(uint256 amountDsToMint) public moreThanZero(amountDsToMint) nonReentrant {
        s_DSMinted[msg.sender] += amountDsToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_ds.mint(msg.sender, amountDsToMint);
        if (!minted) {
            revert DSEngine__MintFailed();
        }
    }

    function burnDs(uint256 amountDsToBurn) public moreThanZero(amountDsToBurn) nonReentrant {
        _burnDs(amountDsToBurn, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Follows CEI: Checks, Effects, Interactions
     * @param collateral The erc20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DS you want to burn to improve the users health factor
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the users funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize the liquidators.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSEngine__HealthFactorOk();
        }
        // A user: $140 ETH, $100 DS
        // debtToCover = $100
        // $100 of DS = ??? ETH
        // $2000 / ETH
        // 0.05 ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // 0.05 ETH * 0.1 = 0.005 ETH
        uint256 bonusCollateral = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;
        // 0.05 ETH + 0.005 ETH = 0.055ETH
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDs(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *  Private & Internal View Functions
     *
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDsMinted, uint256 collateralValueInUsd)
    {
        totalDsMinted = s_DSMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);

        return (totalDsMinted, collateralValueInUsd);
    }

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     *
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDsMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        if (totalDsMinted == 0) {
            return type(uint256).max; // Return the maximum possible uint256 value
        }

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // example1
        // $150 ETH / 100 DS = 1.5
        // 150 * 50 = 7500 / 100 => (75 / 100) < 1

        // example2
        // $1000 ETH / 100 DS = 10
        // 1000 * 50 = 50,000 / 100 => (500 / 100) > 1

        return (collateralAdjustedForThreshold * PRECISION / totalDsMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSEngine__TransferFailed();
        }
    }

    /**
     *
     * @dev Low-level internal function, do not call unless the function calling it is checking for health factors being broken
     */
    function _burnDs(uint256 amountDsToBurn, address onBehalfOf, address dsFrom) private {
        s_DSMinted[onBehalfOf] -= amountDsToBurn;
        bool success = i_ds.transferFrom(dsFrom, address(this), amountDsToBurn);
        if (!success) {
            revert DSEngine__TransferFailed();
        }
        i_ds.burn(amountDsToBurn);
    }

    /**
     *  Public & External View Functions
     *
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }

        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData(); // The returned value will be 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // price of ETH(token)
        // $ / ETH ETH ?? $2000 / ETH.
        // $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // ($10e18 * 1e18) / ($2000e8 * 1e10) = 0.005 * 1e18 = 5 * 1e15
        return (usdAmountInWei * PRECISION / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDsMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
