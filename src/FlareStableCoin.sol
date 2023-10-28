// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FlareStableCoin is ERC20Burnable, Ownable {
    error FlareStableCoin__MustBeMoreThanZero();
    error FlareStableCoin__BurnAmountExceedsBalance();
    error FlareStableCoin__NotZeroAddress();

    constructor() ERC20("FlareStableCoin", "FSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert FlareStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert FlareStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert FlareStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert FlareStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}