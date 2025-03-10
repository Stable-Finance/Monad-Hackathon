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
        // unix epoch of borrow
        uint256 timestamp;
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
        // max ratio of (value - liens) that users allowed to borrow against
        uint256 max_ltv_ratio;
        // property category
        uint256 type_id;
        // has the property been withdrawn
        bool is_withdrawn;
        // address that owns the property
        address depositor;
        // unix timestamp when property was completed
        uint256 deposit_timestamp;
        // increment when users make interest payments
        // interest will be subtracted from here each month
        uint256 prepaid_interest;
        // if users are charged interest but dont have any prepaid interest
        // it will be marked as unpaid in this variable.
        uint256 unpaid_interest;
        // number of times a payment has been missed
        uint8 n_missed_payments;
        // history of borrows and repayments
        Month[] borrow_history;
    }
    mapping(uint256 => Property) private _properties;

    // Next Property ID
    uint256 private _nextPropertyId = 0;
    
    // address of usdx
    USDX private _usdx;

    // Stablecoins that are accepted for repayment
    mapping(IERC20Metadata => IERC20Metadata) private _accepted_stablecoins;
    
    constructor(
        address stable_manager_,
        USDX usdx_ 
    ) ERC721("Stable Property Deposit Manager", "SPD") Ownable(stable_manager_) {
        _usdx = usdx_;
    }

    // Core Property Functionality

    // called by manager address to deposit the house
    function depositProperty(
        uint256 value,
        uint256 liens,
        uint256 max_ltv_ratio,
        uint256 type_id,
        address depositor
    ) onlyOwner external returns (uint256 propertyId) {
        propertyId = _nextPropertyId++;
        
        Property storage property = _properties[propertyId];
        property.value = value;
        property.outstanding_debt = 0;
        property.outstanding_liens = liens;
        property.max_ltv_ratio = max_ltv_ratio;
        property.type_id = type_id;
        property.is_withdrawn = false;
        property.depositor = depositor;
        property.deposit_timestamp = block.timestamp;
        property.prepaid_interest = 0;
        property.unpaid_interest = 0;
        property.n_missed_payments = 0;

        ensureDebtHistoryTabulated(propertyId);

        _mint(depositor, propertyId);
    }

    // Called by Depositor or Stable to borrow against the property.
    function borrow(uint256 propertyId, uint256 value) external {
        require(propertyId < _nextPropertyId, "Invalid Property ID");
        require(value > 0, "Invalid Value");

        Property storage property = _properties[propertyId];
        require(!property.is_withdrawn, "Property Already Withdrawn");
        require(!hasAccountExpired(propertyId), "Property Expired");
        require(
            msg.sender == property.depositor || msg.sender == owner(),
            "Only Callable by Depositor or Owner"
        );
        require(property.n_missed_payments < 3, "Missed Too Many Payments");

        ensureDebtHistoryTabulated(propertyId);

        uint256 new_borrow_amt = property.outstanding_debt + value;
        require(
            new_borrow_amt <= (property.value - property.outstanding_debt) * property.max_ltv_ratio / 1e9,
            "Borrowing Exceeds Max LTV"
        );
        
        // add borrow to events
        Month storage month = property.borrow_history[property.borrow_history.length - 1];
        month.debt_change_events.push(DebtChangeEvent({
            is_borrow: true,
            value: value,
            timestamp: block.timestamp
        }));

        // emit events
        _usdx.mint(msg.sender, value);
    }

    // Property owner can repay the borrow with any accepted stablecoin
    function repayBorrow(uint256 propertyId, IERC20Metadata stablecoinAddress, uint256 payment) external {
        require(isStablecoinAccepted(stablecoinAddress), "Stablecoin Not Accepted");
        require(propertyId < _nextPropertyId, "Invalid Property ID");

        Property storage property = _properties[propertyId];
        require(!property.is_withdrawn, "Property Already Withdrawn");

        ensureDebtHistoryTabulated(propertyId);

        if (address(stablecoinAddress) == address(_usdx)) {
            _usdx.burn(payment);
        } else {
            stablecoinAddress.safeTransferFrom(msg.sender, owner(), payment);
        }

        uint8 decimals = stablecoinAddress.decimals();
        uint256 normalized_payment = normalizePayment(decimals, payment);
        require(normalized_payment > 0, "Normalized Payment Cannot be Zero");

        require(normalized_payment <= property.outstanding_debt, "Cannot Overpay Debt");
        property.outstanding_debt -= normalized_payment;

        Month storage month = property.borrow_history[property.borrow_history.length - 1];
        month.debt_change_events.push(DebtChangeEvent({
            is_borrow: false,
            value: normalized_payment,
            timestamp: block.timestamp
        }));
        // emit events
    }
    
    // Property owner can make payment with a given stablecoin
    function makePayment(uint256 propertyId, IERC20Metadata stablecoinAddress, uint256 payment) external {
        require(isStablecoinAccepted(stablecoinAddress), "Stablecoin Not Accepted");
        require(propertyId < _nextPropertyId, "Invalid Property ID");

        Property storage property = _properties[propertyId];
        require(!property.is_withdrawn, "Property Already Withdrawn");
        
        ensureDebtHistoryTabulated(propertyId);

        if (address(stablecoinAddress) == address(_usdx)) {
            _usdx.burn(payment);
        } else {
            stablecoinAddress.safeTransferFrom(msg.sender, owner(), payment);
        }

        uint8 decimals = stablecoinAddress.decimals();
        uint256 normalized_payment = normalizePayment(decimals, payment);
        require(normalized_payment > 0, "Normalized Payment Cannot be Zero");
        
        // If the payment more than covers unpaid interest then pay all the interest
        // and move the rest into prepaid interest. Otherwise just subtract it from
        // unpaid interest.
        if (normalized_payment > property.unpaid_interest) {
            property.prepaid_interest += normalized_payment - property.unpaid_interest;
            property.unpaid_interest = 0;
        } else {
            property.unpaid_interest -= normalized_payment;
        }
    }

    // Increment 
    function withdrawProperty(uint256 propertyId) external {
        require(propertyId < _nextPropertyId, "Invalid Property ID");

        Property storage property = _properties[propertyId];
        require(!property.is_withdrawn, "Property Already Withdrawn");

        require(msg.sender == property.depositor, "Only Callable By Depositor");
        require(property.outstanding_debt == 0, "Outstanding Debt must be Zero");
        
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
        return (stablecoinAddress == _usdx) ||
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
    
    function hasAccountExpired(uint256 propertyId) public view returns (bool) {
        require(propertyId < _nextPropertyId, "Invalid Property ID");

        Property storage property = _properties[propertyId];

        return getCurrentMonth(property.deposit_timestamp) > 24;
    }

    function ensureDebtHistoryTabulated(uint256 propertyId) public {
        require(propertyId < _nextPropertyId, "Invalid Property ID");

        Property storage property = _properties[propertyId];
        Month[] storage borrow_history = property.borrow_history;

        uint256 current_month = getCurrentMonth(property.deposit_timestamp);
        bool has_finished = current_month > 24;
        uint256 should_be_up_to = Math.min(current_month + 1, 24);

        if (borrow_history.length != should_be_up_to) {
            uint256 idx = borrow_history.length;
            while (borrow_history.length < should_be_up_to) {
                // build history
                
                if (idx == 0) {
                    Month storage month = borrow_history.push();
                    month.starting_outstanding_debt = 0;
                    month.ending_outstanding_debt = 0;
                    month.interest_owed_for_month = 0;
                    month.fully_tabulated = false;
                    month.starting_timestamp = property.deposit_timestamp;
                    month.ending_timestamp = BokkyPooBahsDateTimeLibrary.addMonths(property.deposit_timestamp, 1) - 1;
                } else {
                    Month storage last_month = borrow_history[idx - 1];
                    if (!last_month.fully_tabulated) {
                        // fully tabulate last month
                        tabulate_monthly_interest(property, last_month);
                    }
                    Month storage month = borrow_history.push();
                    month.starting_outstanding_debt = last_month.ending_outstanding_debt;
                    month.ending_outstanding_debt = 0;
                    month.interest_owed_for_month = 0;
                    month.fully_tabulated = false;
                    month.starting_timestamp = BokkyPooBahsDateTimeLibrary.addMonths(property.deposit_timestamp, idx);
                    month.ending_timestamp = BokkyPooBahsDateTimeLibrary.addMonths(property.deposit_timestamp, idx + 1) - 1;
                }
                idx += 1;
            }
        }

        if (has_finished) {
            if (!borrow_history[24].fully_tabulated) {
                // tabulate final month
                tabulate_monthly_interest(property, borrow_history[24]);
            }
        }
    }

    function tabulate_monthly_interest(Property storage property, Month storage month) internal {
        // renting money by the dollar * seconds
        // 0.06 per dollar * yr
        // 0.00016438356 per dollar * second
        uint256 rate  = 1_000_164_383_56;
        uint256 denom = 1_000_000_000_00;
        require(!month.fully_tabulated);
        
        DebtChangeEvent[] storage events = month.debt_change_events;
        uint256 dollar_seconds = 0;
        uint256 amt_borrowed = month.starting_outstanding_debt;
        if (events.length > 0) {
            uint256 idx = 0;
            uint256 last_timestamp = month.starting_timestamp;
            while (idx < events.length) {
                DebtChangeEvent storage current_event = events[idx];
                dollar_seconds += amt_borrowed * (current_event.timestamp - last_timestamp);
                
                last_timestamp = current_event.timestamp;
                amt_borrowed = current_event.is_borrow ?
                    amt_borrowed + current_event.value :
                    amt_borrowed - current_event.value;
                idx += 1;
            }

            dollar_seconds += amt_borrowed * (month.ending_timestamp - last_timestamp);
        } else {
            dollar_seconds = amt_borrowed * (month.ending_timestamp - month.starting_timestamp);
        }

        uint256 monthly_interest = dollar_seconds * rate * denom;

        month.interest_owed_for_month = monthly_interest;
        month.ending_outstanding_debt = amt_borrowed;

        // charge interest
        if (monthly_interest > property.prepaid_interest) {
            property.n_missed_payments += 1;
            property.unpaid_interest += monthly_interest - property.prepaid_interest;
            property.prepaid_interest = 0;
            // emit events
        } else {
            property.prepaid_interest -= monthly_interest;
            // emit events
        }

        month.fully_tabulated = true;
    }
}
