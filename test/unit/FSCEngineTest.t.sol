// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {FSCEngine} from "../../src/FSCEngine.sol";
import {DeployFSC} from "../../script/DeployFSC.s.sol";
import {FlareStableCoin} from "../../src/FlareStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFtsoRegistry} from "../mocks/MockFtsoRegistry.sol";

contract FSCEngineTest is Test {
    DeployFSC deployer;
    FlareStableCoin fsc;
    FSCEngine fsce;
    HelperConfig config;
    string symbol;
    address wflr;
    address ftso;
    MockFtsoRegistry mockRegistry;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() public {
        deployer = new DeployFSC();
        (fsc, fsce, config) = deployer.run();
        (symbol, wflr, ftso,) = config.activeNetworkConfig();
        ERC20Mock(wflr).mint(USER, STARTING_ERC20_BALANCE);
        mockRegistry = MockFtsoRegistry(ftso);
        mockRegistry.setPriceForSymbol("FLR", 1000e8, block.timestamp, 18);
    }

    ////////////////////////////////
    ////// Constructor Tests //////
    //////////////////////////////

    function testConstructorStoresValues() public {
        assertEq(fsce.getCollateralTokenSymbol(), symbol);
        assertEq(fsce.getCollateralTokenAddress(), address(wflr));
        assertEq(address(fsce.getFscContract()), address(fsc));
    }

    //////////////////////////
    ////// Price Tests //////
    ////////////////////////

    function testMockPriceIsSetCorrectly() public {
        (uint256 price,, uint256 decimals) = mockRegistry.getCurrentPriceWithDecimals(symbol);
        assertEq(price, 1000e8);
        assertEq(decimals, 18);
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 1000/ETH = 15,000e18
        uint256 expectedUsd = 15000e18;
        uint256 actualUsd = fsce.getUsdValue(symbol, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $1000 / ETH, $100
        uint256 expectedWflr = 0.1 ether;
        uint256 actualWflr = fsce.getTokenAmountFromUsd(symbol, usdAmount);
        assertEq(expectedWflr, actualWflr);
    }

    // //////////////////////////////////////
    // ////// depositCollateral Tests //////
    // ////////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(wflr).approve(address(fsce), AMOUNT_COLLATERAL);
        vm.expectRevert(FSCEngine.FSCEngine__NeedsMoreThanZero.selector);
        fsce.depositCollateral(wflr, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(FSCEngine.FSCEngine__NotAllowedToken.selector);
        fsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wflr).approve(address(fsce), AMOUNT_COLLATERAL);
        fsce.depositCollateral(wflr, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalFscMinted, uint256 collateralValueInUsd) = fsce.getAccountInformation(USER);
        uint256 expectedTotalFscMinted = 0;
        uint256 expectedDepositAmount = fsce.getTokenAmountFromUsd(symbol, collateralValueInUsd);
        assertEq(totalFscMinted, expectedTotalFscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    /////////////////////////
    //// mintFsc Tests /////
    ///////////////////////

    function testRevertsIfMintAmountZero() public {
        vm.startPrank(USER);
        vm.expectRevert(FSCEngine.FSCEngine__NeedsMoreThanZero.selector);
        fsce.mintFsc(0);
        vm.stopPrank();
    }

    function testCanMintFsc() public depositedCollateral {
        uint256 mintAmount = AMOUNT_COLLATERAL / 2;
        vm.startPrank(USER);
        fsce.mintFsc(mintAmount);
        (uint256 totalFscMinted,) = fsce.getAccountInformation(USER);
        assertEq(totalFscMinted, mintAmount);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public {
        (uint256 price,) = mockRegistry.getCurrentPrice(symbol);
        amountToMint = (amountCollateral * (price * fsce.getAdditionalFeedPrecision())) / fsce.getPrecision();

        vm.startPrank(USER);
        ERC20Mock(wflr).approve(address(fsce), amountCollateral);
        fsce.depositCollateral(wflr, amountCollateral);

        uint256 expectedHealthFactor =
            fsce.calculateHealthFactor(amountToMint, fsce.getUsdValue(symbol, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(FSCEngine.FSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        fsce.mintFsc(amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedCcsc() {
        vm.startPrank(USER);
        ERC20Mock(wflr).approve(address(fsce), amountCollateral);
        fsce.depositCollateralAndMintFsc(wflr, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    // ///////////////////////////////
    // ////// burnFsc() Tests ///////
    // //////////////////////////////

    function testCanBurnFsc() public depositedCollateral {
        uint256 mintAmount = AMOUNT_COLLATERAL / 2;
        vm.startPrank(USER);
        fsce.mintFsc(mintAmount);
        fsc.approve(address(fsce), mintAmount); // approve the FSCEngine to burn the minted FSC
        // Burn the FSC
        uint256 fscToBurn = 1 ether; // 1 FSC
        fsce.burnFsc(fscToBurn);
        // Check the balance
        uint256 remainingFsc = fsc.balanceOf(USER);
        assertEq(remainingFsc, mintAmount - fscToBurn);
        vm.stopPrank();
    }

    function testRevertsIfBurnZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(FSCEngine.FSCEngine__NeedsMoreThanZero.selector);
        fsce.burnFsc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        fsce.burnFsc(1);
    }

    ////////////////////////////////////////////////
    ////// depositCollateralAndMintDsc Tests //////
    //////////////////////////////////////////////

    function testCanDepositCollateralAndMintFsc() public {
        vm.startPrank(USER);
        ERC20Mock(wflr).approve(address(fsce), AMOUNT_COLLATERAL);
        fsce.depositCollateralAndMintFsc(wflr, AMOUNT_COLLATERAL, (AMOUNT_COLLATERAL / 2));
        uint256 remainingFsc = fsc.balanceOf(USER);
        assertEq(remainingFsc, AMOUNT_COLLATERAL / 2);
        vm.stopPrank();
    }

    //////////////////////////////
    ////// liquidate Tests //////
    ////////////////////////////

    function testRevertsLiquidateIfHealthFactorOk() public {
        ERC20Mock(wflr).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(wflr).approve(address(fsce), collateralToCover);
        fsce.depositCollateralAndMintFsc(wflr, collateralToCover, amountToMint);
        fsc.approve(address(fsce), amountToMint);

        vm.expectRevert(FSCEngine.FSCEngine__HealthFactorOk.selector);
        fsce.liquidate(symbol, USER, amountToMint);
        vm.stopPrank();
    }

    ///////////////////////////
    ////// getter Tests //////
    /////////////////////////

    function testGetFscContract() public {
        vm.startPrank(USER);
        FlareStableCoin expectedFscContract = fsc;
        FlareStableCoin fetchedFscContract = fsce.getFscContract();
        assertEq(address(fetchedFscContract), address(expectedFscContract));
        vm.stopPrank();
    }
}
