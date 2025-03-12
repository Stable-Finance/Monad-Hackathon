// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDT is ERC20 {
   constructor(uint256 mint_val) ERC20("Mock Tether USDC", "USDT") {
      _mint(msg.sender, mint_val);
   }

   function decimals() public pure override returns (uint8) {
      return 8;
   }
}