// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {Script} from "forge-std/Script.sol";
import {FlareStableCoin} from "../src/FlareStableCoin.sol";
import {FSCEngine} from "../src/FSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {MockFtsoRegistry} from "../test/mocks/MockFtsoRegistry.sol";

contract DeployFSC is Script {
    function run() external returns (FlareStableCoin, FSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (string memory collateralSymbol, address collateralToken, address ftsoRegistry, uint256 deployerKey) =
            config.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        FlareStableCoin fsc = new FlareStableCoin();
        FSCEngine engine = new FSCEngine(collateralSymbol, collateralToken,  address(fsc), address(ftsoRegistry));
        fsc.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (fsc, engine, config);
    }
}
