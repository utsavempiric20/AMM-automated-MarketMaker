// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract XToken is ERC20 {
    constructor(uint256 _initialSupply) ERC20("XToken", "XT") {
        _mint(msg.sender, _initialSupply);
    }
}
