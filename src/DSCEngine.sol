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
    error DSCEngine__NotZeroAddress();
    error DSCEngine__TransferFailed();
    error DSCEngine__CollateralMustBeGreaterThanZero();
    error DSCEngine__HealthFactorNotMet();
    error DSCEngine__TokenAndPriceFeedAddressMustBeSameLenght();

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposit;

    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);


    modifier morethanZero(uint256 amount) {
        if (amount <= 0){
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

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        if(tokenAddresses.length != priceFeedAddress.length){
            revert DSCEngine__TokenAndPriceFeedAddressMustBeSameLenght();
        }

        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] = priceFeedAddress[i];
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc() external{}

    /** 
     * @notice Follows CEI.
     * @param tokenCollateralAddress The address of the collateral token to deposit
     * @param amountCollateral amount of collateral to deposit
     * @notice This function allows users to deposit collateral and mint DSC in a single transaction.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external morethanZero(amountCollateral) isTokenAllowed(tokenCollateralAddress) nonReentrant {
        s_collateralDeposit[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external{}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

}