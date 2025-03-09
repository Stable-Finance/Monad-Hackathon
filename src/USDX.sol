// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract USDX is ERC20, Ownable {
    constructor(address _usdx_manager) ERC20("Stable USD", "USDX") Ownable(_usdx_manager) {}

    function mint(address account, uint256 value) external onlyOwner {
        _mint(account, value);
    }

    function decimals() public pure override returns(uint8) {
        return 6;
    }
}