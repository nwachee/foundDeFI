//SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Nwachee
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////
    // Errors
    ///////////////
    error DSCEngine__NotZeroAddress();
    error DSCEngine__TransferFailed();
    error DSCEngine__CollateralMustBeGreaterThanZero();
    error DSCEngine__HealthFactorNotMet(uint256 healthFactor);
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__TokenAndPriceFeedAddressMustBeSameLenght();

    ///////////////////
    // State Variables
    ///////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 50;
    uint256 private constant HEALTH_FACTOR_LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposit;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////
    // Events
    ////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    ///////////////////
    // Modifiers
    ///////////////////
    modifier morethanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__CollateralMustBeGreaterThanZero();
        }
        _;
    }

    modifier isTokenAllowed(address token) {
        if (s_priceFeed[token] == address(0)) {
            revert DSCEngine__NotZeroAddress();
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAndPriceFeedAddressMustBeSameLenght();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////
    // External Functions
    ///////////////////

    /**
     * @notice Follows CEI.
     * @param tokenCollateralAddress The address of the collateral token to deposit
     * @param amountCollateral amount of collateral to deposit
     * @param amountDscToMint amount of DSC to mint
     * @notice This function allows users to deposit collateral and mint DSC in a single transaction.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice Follows CEI.
     * @param tokenCollateralAddress The address of the collateral token to deposit
     * @param amountCollateral amount of collateral to deposit
     * @notice This function allows users to deposit collateral and mint DSC in a single transaction.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        morethanZero(amountCollateral)
        isTokenAllowed(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposit[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice Follows CEI.
     * @param tokenCollateralAddress The address of the collateral token to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToMint The amount of DSC to mint
     * @notice This function Burns DSC and allows users to redeem collateral.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint)
        external
    {
        burnDsc(amountDscToMint);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateral, uint256 amountCollateral)
        public
        morethanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateral, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorNotMet(msg.sender);
    }

    /**
     * @notice Follows CEI.
     * @param amountDscToMint The amount of DSC to mint
     * @notice This function allows users to mint DSC by depositing collateral.
     */
    function mintDsc(uint256 amountDscToMint) public morethanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorNotMet(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__TransferFailed();
        }
    }

    function burnDsc(uint256 amount) public morethanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorNotMet(msg.sender);
    }

    /*
     * @notice Function to liquidate a user.
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
     * to work.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        morethanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotMet(startingUserHealthFactor);
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 collateralBonus = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + collateralBonus;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
    }

    function getHealthFactor() external view {}

    //////////////////////////////
    // Private & Internal View & Pure Functions
    //////////////////////////////

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateral, uint256 amountCollateral, address from, address to) private {
        s_collateralDeposit[msg.sender][tokenCollateral] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateral, amountCollateral);
        bool success = IERC20(tokenCollateral).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 collateralValueInUsd, uint256 totalDscMinted)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice This function calculates the health factor of a user.
     * The health factor is defined as the ratio of the value of collateral to the value of DSC minted.
     * If the health factor is below a certain threshold, the user is at risk of liquidation.
     * @param user The address of the user to calculate the health factor for
     * @return The health factor of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 collateralValueInUsd, uint256 totalDscMinted) = _getAccountInformation(user);
        uint256 collateralAdjustedForPrecision =
            (collateralValueInUsd * HEALTH_FACTOR_LIQUIDATION_THRESHOLD) / HEALTH_FACTOR_LIQUIDATION_PRECISION;
        return (collateralAdjustedForPrecision * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorNotMet(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotMet(userHealthFactor);
        }
    }

    //////////////////////////////
    // Public & External View Functions
    //////////////////////////////
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        //Loop through all collateral tokens, get the amount of each token deposited by the user, map it to the price, to get the total value of collateral in USD
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposit[user][token];
            totalCollateralValueInUsd += getUsdValue(amount, token);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(uint256 amount, address token) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
