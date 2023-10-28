// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFtsoRegistry} from "../test/mocks/MockFtsoRegistry.sol";
import {IFlareContractRegistry} from
    "@flarenetwork/flare-periphery-contracts/flare/util-contracts/userInterfaces/IFlareContractRegistry.sol";
import {IFtsoRegistry} from "@flarenetwork/flare-periphery-contracts/flare/ftso/userInterfaces/IFtsoRegistry.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        string collateralSymbol;
        address collateralToken;
        address ftsoRegistry;
        uint256 deployerKey;
    }

    address private constant FLARE_CONTRACT_REGISTRY = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    IFlareContractRegistry contractRegistry = IFlareContractRegistry(FLARE_CONTRACT_REGISTRY);
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 14) {
            activeNetworkConfig = getFlareConfig();
        } else if (block.chainid == 19) {
            activeNetworkConfig = getSongbirdConfig();
        } else if (block.chainid == 114) {
            activeNetworkConfig = getCoston2Config();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getFlareConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            collateralSymbol: "FLR",
            collateralToken: 0x1D80c49BbBCd1C0911346656B529DF9E5c2F783d, // contract address for WFLR
            ftsoRegistry: contractRegistry.getContractAddressByName("FtsoRegistry"),
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getSongbirdConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            collateralSymbol: "SGB",
            collateralToken: 0x02f0826ef6aD107Cfc861152B32B52fD11BaB9ED, // contract address for WSGB
            ftsoRegistry: contractRegistry.getContractAddressByName("FtsoRegistry"),
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getCoston2Config() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            collateralSymbol: "FLR",
            collateralToken: 0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273, // contract address for WC2FLR
            ftsoRegistry: contractRegistry.getContractAddressByName("FtsoRegistry"),
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        vm.startBroadcast();
        ERC20Mock token = new ERC20Mock();
        MockFtsoRegistry registry = new MockFtsoRegistry();
        vm.stopBroadcast();
        return NetworkConfig({
            collateralSymbol: "FLR",
            collateralToken: address(token),
            ftsoRegistry: address(registry),
            deployerKey: vm.envUint("ANVIL_PRIVATE_KEY")
        });
    }
}
