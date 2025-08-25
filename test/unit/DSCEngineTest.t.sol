//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    MockV3Aggregator public ethUsdPriceFeedMock;
    MockV3Aggregator public btcUsdPriceFeedMock;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_AMOUNT = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        // Only cast feeds to MockV3Aggregator when running on Anvil
        if (block.chainid == 31337) {
            ethUsdPriceFeedMock = MockV3Aggregator(ethUsdPriceFeed);
            btcUsdPriceFeedMock = MockV3Aggregator(btcUsdPriceFeed);
        }

        ERC20Mock(weth).mint(USER, STARTING_ERC20_AMOUNT);
    }

    ///////////////////////////
    // Constructor Tests //////
    ///////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function test_RevertsIfTokenLengthNotEqualPriceFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAndPriceFeedAddressMustBeSameLenght.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////
    // Price Tests //
    /////////////////

    function test_GetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function test_GetUsdValue() public {
        // 15e18 * 2,000/ETH = 30,000e18
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(ethAmount, weth);
        assertEq(expectedUsd, actualUsd);
    }

    /////////////////
    // deposit Tests //
    /////////////////

    function test_RevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__CollateralMustBeGreaterThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_RevertIfCollateralIsNotApproved() public {
        ERC20Mock sandToken = new ERC20Mock("SAND", "SAND", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(sandToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        _;
        vm.stopPrank();
    }

    function test_CanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 collateralValueInUsd, uint256 totalDscMinted) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getUsdValue(AMOUNT_COLLATERAL, weth);
        assertEq(collateralValueInUsd, expectedDepositAmount);
        assertEq(totalDscMinted, expectedTotalDscMinted);
    }

    function test_DepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        uint256 amountToMint = 1000 ether; // safe amount within health factor
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);

        (uint256 collateralValueInUsd, uint256 totalDscMinted) = dsce.getAccountInformation(USER);

        assertEq(totalDscMinted, amountToMint);
        assertEq(collateralValueInUsd, dsce.getUsdValue(AMOUNT_COLLATERAL, weth));
        vm.stopPrank();
    }

    function test_CanMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 1000 ether;
        dsce.mintDsc(amountToMint);

        (, uint256 totalDscMinted) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, amountToMint);
        vm.stopPrank();
    }

    function test_RevertIfHealthFactorBrokenOnMint() public depositedCollateral {
        vm.startPrank(USER);
        uint256 unsafeMintAmount = 1e30; // absurd amount to break health factor
        vm.expectRevert();
        dsce.mintDsc(unsafeMintAmount);
        vm.stopPrank();
    }

    function test_CanBurnDsc() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 1000 ether;
        dsce.mintDsc(amountToMint);

        dsc.approve(address(dsce), amountToMint);
        dsce.burnDsc(amountToMint);

        (, uint256 totalDscMinted) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        vm.stopPrank();
    }

    function test_RevertIfBurnZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__CollateralMustBeGreaterThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function test_CanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, true);
        emit DSCEngine.CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);

        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);

        (uint256 collateralValueInUsd,) = dsce.getAccountInformation(USER);
        assertEq(collateralValueInUsd, 0);
        vm.stopPrank();
    }
}
