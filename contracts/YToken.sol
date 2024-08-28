// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract YToken is ERC20 {
    constructor(uint256 _initialSupply) ERC20("YToken", "YT") {
        _mint(msg.sender, _initialSupply);
    }
}
