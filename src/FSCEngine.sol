// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {FlareStableCoin} from "./FlareStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFlareContractRegistry} from
    "@flarenetwork/flare-periphery-contracts/flare/util-contracts/userInterfaces/IFlareContractRegistry.sol";
import {IFtsoRegistry} from "@flarenetwork/flare-periphery-contracts/flare/ftso/userInterfaces/IFtsoRegistry.sol";

contract FSCEngine is ReentrancyGuard, Ownable {
    error FSCEngine__NeedsMoreThanZero();
    error FSCEngine__NotAllowedToken();
    error FSCEngine__TransferFailed();
    error FSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error FSCEngine__MintFailed();
    error FSCEngine__HealthFactorOk();
    error FSCEngine__HealthFactorNotImproved();

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus

    mapping(address user => uint256 amount) private s_collateralDeposited;
    mapping(address user => uint256 amountFscMinted) private s_FSCMinted;
    mapping(string _symbol => address collateralToken) private s_symbolToAddress;
    string private s_symbol;

    address private immutable i_collateralToken;
    FlareStableCoin private immutable i_fsc;
    IFtsoRegistry private immutable i_ftsoRegistry;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert FSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (i_collateralToken != token) {
            revert FSCEngine__NotAllowedToken();
        }
        _;
    }

    constructor(string memory _symbol, address tokenAddress, address fscAddress, address ftsoRegistry) {
        s_symbol = _symbol;
        i_collateralToken = tokenAddress;
        s_symbolToAddress[_symbol] = i_collateralToken;
        i_fsc = FlareStableCoin(fscAddress);
        i_ftsoRegistry = IFtsoRegistry(ftsoRegistry);
    }

    //////////////////////////////
    //// External Functions /////
    ////////////////////////////

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountFscToMint The amount of FSC to mint
     * @notice This function will deposit your collateral and mint FSC in one transaction
     */
    function depositCollateralAndMintFsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountFscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintFsc(amountFscToMint);
    }

    /**
     * @notice follows CEI (Checks, Effects, Interaction)
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert FSCEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountFscToBurn The amount of FSC to burn
     * This function burns FSC and redeems the underlying collateral in one transaction
     */
    function redeemCollateralForFsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountFscToBurn)
        external
    {
        burnFsc(amountFscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    // In order to redeem collateral:
    // 1. Health factor must be over 1 AFTER collateral pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Follows CEI
     * @param amountFscToMint The amount of FSC to mint
     * @notice User must have more collateral value than the minimum threshold
     */
    function mintFsc(uint256 amountFscToMint) public moreThanZero(amountFscToMint) nonReentrant {
        s_FSCMinted[msg.sender] += amountFscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_fsc.mint(msg.sender, amountFscToMint);
        if (!minted) {
            revert FSCEngine__MintFailed();
        }
    }

    function burnFsc(uint256 amount) public moreThanZero(amount) {
        _burnFsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // unlikely to ever hit when burning debt
    }

    /**
     * @param _symbol The Symbol of the ERC20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FAT
     * @param debtToCover The amount of FSC you want to burn to improve the users health factor
     * @notice You can partially liquid a user.
     * @notice You will get a liquidation bonus for taking the users funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     */
    function liquidate(string memory _symbol, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert FSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(_symbol, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, s_symbolToAddress[_symbol], totalCollateralToRedeem);
        _burnFsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert FSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /////////////////////////////////////////////
    //// Private & Internal View Functions /////
    ///////////////////////////////////////////

    /**
     * @dev Low-level internal function -
     * Do not call unless the function calling it is checking for health factors being broken.
     */
    function _burnFsc(uint256 amountFscToBurn, address onBehalfOf, address fscFrom) private {
        s_FSCMinted[onBehalfOf] -= amountFscToBurn;
        bool success = i_fsc.transferFrom(fscFrom, address(this), amountFscToBurn);
        // This condition is hypothetically unreachable because if there is a failure, revert will come from transferFrom()
        if (!success) {
            revert FSCEngine__TransferFailed();
        }
        i_fsc.burn(amountFscToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert FSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalFscMinted, uint256 collateralValueInUsd)
    {
        totalFscMinted = s_FSCMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    /**
     * Returns how close to liquidation a user is.
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalFscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalFscMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert FSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalFscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalFscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalFscMinted;
    }

    /////////////////////////////////////////////
    //// Public & External View Functions //////
    ///////////////////////////////////////////

    function calculateHealthFactor(uint256 totalFscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalFscMinted, collateralValueInUsd);
    }

    function getTokenAmountFromUsd(string memory _symbol, uint256 usdAmountInWei) public view returns (uint256) {
        (uint256 _price,) = i_ftsoRegistry.getCurrentPrice(_symbol);
        return (usdAmountInWei * PRECISION) / (_price * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 amount = s_collateralDeposited[user];
        totalCollateralValueInUsd += getUsdValue(getCollateralTokenSymbol(), amount);
        return totalCollateralValueInUsd;
    }

    function getUsdValue(string memory _symbol, uint256 amount) public view returns (uint256) {
        (uint256 _price,) = i_ftsoRegistry.getCurrentPrice(_symbol);
        return ((_price * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalFscMinted, uint256 collateralValueInUsd)
    {
        (totalFscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralTokenSymbol() public view returns (string memory) {
        return s_symbol;
    }

    function getCollateralTokenAddress() public view returns (address) {
        return i_collateralToken;
    }

    function getFscContract() public view returns (FlareStableCoin) {
        return i_fsc;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getCollateralBalanceOfUser(address user) external view returns (uint256) {
        return s_collateralDeposited[user];
    }
}
