// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract USDX is Initializable, ERC20Upgradeable, AccessControlUpgradeable {
    bytes32 public constant MINTER = keccak256("MINTER");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) initializer public {
        __ERC20_init("Stable USD", "USDX");
        __AccessControl_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function mint(address account, uint256 value) external onlyRole(MINTER) {
        _mint(account, value);
    }

    function adminUpdate(address from, address to, uint256 value) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _update(from, to, value);
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }

    function decimals() public pure override returns(uint8) {
        return 6;
    }
}