// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title USDX
 * @author Matthew Jurenka <matthew@jurenka.software>
 * @notice 
 *
 * USDX is a stablecoin that can be generated by depositing properties
 * and other RWAs into the StablePropertyDepositManager.
 * Functionally it is a relatively simple ERC20 contract that gives the Owner
 * control of balances, similar to USDC.
 */
contract USDX is Initializable, ERC20Upgradeable, AccessControlUpgradeable {
    bytes32 public constant MINTER = keccak256("MINTER");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * 
     * @param admin Address that will have admin perms
     *   Should be a multisig controlled by Stable
     */
    function initialize(address admin) initializer public {
        __ERC20_init("Stable USD", "USDX");
        __AccessControl_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @param account The account that will receive tokens
     * @param value Amount of tokens to mint
     */
    function mint(address account, uint256 value) external onlyRole(MINTER) {
        _mint(account, value);
    }

    /**
     * For compliance purposes Stable needs to be able to have ultimate control over
     * which wallets and accounts can have access to USDX
     */
    function adminUpdate(address from, address to, uint256 value) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _update(from, to, value);
    }

    /**
     * Any user is able to burn their own USDX. This is highly
     * discouraged but is possible anyway by sending to 0x0 address.
     * @param value amount of tokens to burn
     */
    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }

    /**
     * Similar to USDC and USDT, USDX uses 6 decimals
     */
    function decimals() public pure override returns(uint8) {
        return 6;
    }
}