// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import { USDX } from "./USDX.sol";

import "@BokkyPooBahsDateTimeLibrary/BokkyPooBahsDateTimeLibrary.sol";

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
        // starting and ending timestamps for the month
        uint256 starting_timestamp;
        uint256 ending_timestamp;
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
        // max ratio of (value - lients) that users allowed to borrow against
        uint256 max_ltv;
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
        
        _properties[tokenId] = Property({
            value: value,
            outstanding_debt: 0,
            outstanding_liens: liens,
            max_ltv: max_ltv,
            type_id: type_id,
            is_withdrawn: false,
            depositor: depositor,
            deposit_timestamp: block.timestamp,
            borrow_history: new Month[](0)
        });

        _mint(depositor, tokenId);
    }
    
    function withdraw(uint256 x) external {

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
        //require(property.repaid_debt >= property.outstanding_debt, "Debt Not Repaid");
        
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

    function getCurrentMonth(uint256 starting_timestamp) internal view returns (uint256) {
        return BokkyPooBahsDateTimeLibrary.diffMonths(starting_timestamp, block.timestamp);
    }

    // Per property
    // keep track of 24 months
    // each month keep track of all borrows and repayments

    function ensureDebtHistoryTabulated(uint256 propertyId) public {
        Property storage property = _properties[propertyId];
        Month[] storage borrow_history = property.borrow_history;

        // 
        uint256 current_month = getCurrentMonth(property.deposit_timestamp);
        bool has_finished = current_month > 24;
        uint256 should_be_up_to = Math.min(current_month + 1, 24);

        if (borrow_history.length != should_be_up_to) {
            uint256 last_idx = borrow_history.length;
            while (borrow_history.length < should_be_up_to) {
                // build history
                Month storage last_month = borrow_history[last_idx];
                if (!last_month.fully_tabulated) {
                    // fully tabulate last month
                    tabulate_monthly_interest(last_month);
                }
                borrow_history.push(Month({
                    starting_outstanding_debt: last_month.ending_outstanding_debt + last_month.interest_owed_for_month,
                    ending_outstanding_debt: 0,
                    interest_owed_for_month: 0,
                    fully_tabulated: false,
                    starting_timestamp: 0,
                    ending_timestamp: 0,
                    debt_change_events: new DebtChangeEvent[](0)
                }));
                last_idx += 1;
            }
        }

        if (has_finished) {
            if (!borrow_history[24].fully_tabulated) {
                // tabulate final month
                tabulate_monthly_interest(borrow_history[24]);
            }
        }
    }

    function tabulate_monthly_interest(Month storage month) internal {
        // renting money by the dollar * seconds
        // 0.06 per yr
        // 0.00016438356 per second
        uint256 rate  = 1_000_164_383_56;
        uint256 denom = 1_000_000_000_00;
        
        DebtChangeEvent[] storage events = month.debt_change_events;
        if (events.length > 0) {
            uint256 dollar_seconds = 0;
        } else {
            month.fully_tabulated = true;
            uint256 elapsed_s = month.ending_timestamp - month.starting_timestamp;
            month.ending_outstanding_debt = month.starting_outstanding_debt * elapsed_s * rate / denom;
        }
    }
}
