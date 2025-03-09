// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { USDX } from "./USDX.sol";

// 2 yr loan, repaid monthly interest only
// 
// borrow 1m owe 60k
// if they miss a payment add 1% of total amount thats
// deposit interest payments in advance
// option to extend or renew with changed interest rate maybe
// to withdraw they pay everything and then get it 30 days later
// deposit and then immediately mint max ltv

// If depegs in the lower direction then borrowers swap into usdx and repay their loan with usdx
// If depegs in the higher direction then borrowers swap out of usdx and repay their loan with usdc/usdt

contract StablePropertyDepositManager is ERC721, Ownable {
    using SafeERC20 for IERC20Metadata;
    
    struct DebtChangeEvent {
        // true if the change represents the user withdrawing more USDX,
        // false if its repaying the loan
        bool is_borrow;
        // amount of the debt change
        uint256 value;
    }
    
    struct Month {
        // false before initialized. must be true before any operations can be done
        bool initialized;
        // Amount of USDX owed by property at start of the month
        uint256 starting_outstanding_debt;
        // Amount of USDX owed by property at end of the month
        // Will be 0 until interest is fully tabulated at the end of the month
        uint256 ending_outstanding_debt;
        // Interest on USDX owed throughout the month.
        // Will be 0 until after the end of the month the interest is fully tabulated
        uint256 interest_owed_for_month;
        // bool that tracks whether or not the interest owed has been calculated
        // will be false until after the end of the month where a function can be called
        // that will complete the calculation for the month.
        bool fully_tabulated;
        // bool that tracks whether or not the interest has been payed late.
        // initially is false, can be set to true if 
        bool late_payment;
        // list of event changes for a particular event
        DebtChangeEvent[] debt_change_events;
    }

    // Information about the property
    struct Property {
        // appraised value of the property
        uint256 value;
        // amount of debt that depositor owes before they can withdraw
        uint256 outstanding_debt;
        // amount of liens discovered against the property
        uint256 outstanding_liens;
        // max ratio that users allowed to borrow against
        uint256 debt_limit;
        // property category
        uint256 type_id;
        // has the property been withdrawn
        bool is_withdrawn;
        // address that owns the property
        address depositor;
        // unix timestamp when property was completed
        uint256 deposit_timestamp;
        // history of borrows and repayments
        Month[] borrow_history;
    }
    mapping(uint256 => Property) private _properties;

    // Next Property ID
    uint256 private _nextPropertyId = 0;
    
    // address of usdx
    USDX private _usdx_address;

    // Stablecoins that are accepted for repayment
    mapping(IERC20Metadata => IERC20Metadata) private _accepted_stablecoins;
    
    constructor(
        address stable_manager_,
        USDX usdx_address_ 
    ) ERC721("Stable Property Deposit", "SPD") Ownable(stable_manager_) {
        _usdx_address = usdx_address_;
    }

    // Core Property Functionality

    // called by manager address to deposit the house
    function depositHouse(
        uint256 value,
        uint256 liens,
        uint256 max_ltv,
        uint256 type_id,
        address depositor
    ) onlyOwner external {
        uint256 tokenId = _nextPropertyId++;
        
        uint256 loan_value = (value - liens) * max_ltv / 1e9;
        uint256 new_debt = loan_value * 1060000000 / 1e9 * 2;
        _properties[tokenId] = Property({
            value: value,
            outstanding_liens: liens,
            outstanding_debt: new_debt,
            repaid_debt: 0,
            max_ltv_ratio: max_ltv,
            type_id: type_id,
            depositor: depositor,
            is_withdrawn: false
        });

        _usdx_address.mint(depositor, loan_value);

        _mint(depositor, tokenId);
    }

    // Property owner can make payment with a given stablecoin
    function makePayment(uint256 propertyId, IERC20Metadata stablecoinAddress, uint256 payment) external {
        require(isStablecoinAccepted(stablecoinAddress), "Stablecoin Not Accepted");
        require(propertyId < _nextPropertyId, "Invalid Property ID");

        uint8 decimals = stablecoinAddress.decimals();
        uint256 normalized_payment = normalizePayment(decimals, payment);
        
        stablecoinAddress.safeTransferFrom(msg.sender, owner(), normalized_payment);

        Property storage property = _properties[propertyId];
        require(!property.is_withdrawn, "Property Already Withdrawn");
        property.repaid_debt += normalized_payment;
    }

    // Increases amount to owed if a payment is missed
    function checkPayment() external {
        
    }

    // Increment 
    function withdrawHouse(uint256 propertyId) external {
        require(propertyId < _nextPropertyId, "Invalid Property ID");

        Property storage property = _properties[propertyId];
        require(!property.is_withdrawn, "Property Already Withdrawn");

        require(msg.sender == property.depositor, "Only Callable By Depositor");
        require(property.repaid_debt >= property.outstanding_debt, "Debt Not Repaid");
        
        property.is_withdrawn = true;
        // emit withdrawn event
    }

    // Stablecoin Management
    function addAcceptedStablecoin(IERC20Metadata stablecoinAddress) onlyOwner external {
        _accepted_stablecoins[stablecoinAddress] = stablecoinAddress;
    }

    function removeAcceptedStablecoin(IERC20Metadata stablecoinAddress) onlyOwner external {
        _accepted_stablecoins[stablecoinAddress] = IERC20Metadata(address(0));
    }

    function isStablecoinAccepted(IERC20Metadata stablecoinAddress) private view returns(bool) {
        return (stablecoinAddress == _usdx_address) ||
            (_accepted_stablecoins[stablecoinAddress] != IERC20Metadata(address(0)));
    }

    // Only Stable can transfer properties (note onlyOwner modifier)
    function _checkAuthorized(
        address owner, address spender, uint256 tokenId
    ) onlyOwner internal view override {}

    // Utility Functions

    // Takes a payment with a given amount of decimals and associated value
    // and returns the associated value of USDX (6 decimals)
    function normalizePayment(uint8 decimals, uint256 value) public pure returns (uint256) {
        if (decimals >= 6) {
            return value * (10 ** (decimals - 6));
        } else {
            return value / (10 ** (6 - decimals));
        }
    }

    function getCurrentMonth() {
        
    }
}
