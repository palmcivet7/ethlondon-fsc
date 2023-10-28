# Flare Stable Coin

This project is an exogenously-collateralized stablecoin on the [Flare Network](https://flare.network/), built from a token contract that is owned and controlled by an "engine" contract. The engine contract utilizes the [Flare Time Series Oracle](https://flare.network/ftso/).

## Table of Contents

- [Flare Stable Coin](#flare-stable-coin)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [FlareStableCoin.sol](#flarestablecoinsol)
  - [FSCEngine.sol](#fscenginesol)
  - [HelperConfig.s.sol](#helperconfigssol)
  - [Installation](#installation)
  - [Deployment](#deployment)
  - [Testing](#testing)
  - [License](#license)

## Overview

This project is built from two smart contracts and demonstrates an exogenously-collateralized stablecoin on the Flare Network. The first contract is `FlareStableCoin.sol`, which is a token contract for minting and burning the Flare Stable Coin (FSC). The second contract is `FSCEngine.sol`, which owns and controls the FSC contract. The engine contract uses Flare's native oracle, [Flare Time Series Oracle (FTSO)](https://flare.network/ftso/) to secure the algorithmically generated stablecoin. The Flare Stable Coin keeps its stable price by allowing users to mint an appropriate amount equivalent to their deposit based on oracle prices, and allowing other users to liquidate positions if prices drop too low. The Flare Stable Coin is exogenously-collateralized because the token used for collateral is not native to the FSC system - it can be from anywhere in the Flare Network ecosystem.

## FlareStableCoin.sol

The `FlareStableCoin.sol` contract has a `mint()` and a `burn()` function. These functions can only be called by the owner, `FSCEngine.sol`.

## FSCEngine.sol

The `FSCEngine.sol` contract mints FSC tokens in exchange for over-collateralized deposits. The FSC address, collateral, and collateral's respective FTSO pricefeed gets set in the constructor. The value of the deposited collateral must be more than the FSC that is minted in exchange. If the value of the collateral declines based on price data from FTSO, other users may `liquidate()` a collateralized position to maintain the FSC token's stable value.

## HelperConfig.s.sol

The HelperConfig script dictates the constructor arguments based on the network being deployed to. For demonstration purposes the collateral token has been set to the wrapped equivalent of the network's native token, ie. WFLR for Flare Network and WC2FLR for Coston2.

## Installation

To install the necessary dependencies, first ensure that you have [Foundry](https://book.getfoundry.sh/getting-started/installation) installed by running the following command:

```
curl -L https://foundry.paradigm.xyz | bash
```

Then run the following commands in the project's root directory:

```
foundryup
```

```
forge install
```

## Deployment

The constructor arguments are provided in the HelperConfig script based on the chain being deployed to.

Replace `PRIVATE_KEY` and `YOUR_RPC_URL` in the `.env` with your respective private key and rpc url.

Deploy both the `FlareStableCoin.sol` and the `FSCEngine.sol` contracts by running the following commands:

```
source .env
```

```
forge script script/DeployFSC.s.sol --private-key $PRIVATE_KEY --rpc-url $YOUR_RPC_URL --broadcast
```

## Testing

To run the unit tests run the following command:

```
forge test
```

## License

This project is licensed under the [MIT License](https://opensource.org/license/mit/).
