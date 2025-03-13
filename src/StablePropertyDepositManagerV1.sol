// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import { ERC721EnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PropertyInfo, DebtChangeEvent, Month, Property } from "./IStablePropertyDepositManagerV1.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import { USDX } from "./USDX.sol";
import {HelperLibrary} from "./HelperLibrary.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

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



contract StablePropertyDepositManagerV1 is Initializable, OwnableUpgradeable, ERC721EnumerableUpgradeable {
    using SafeERC20 for IERC20Metadata;
    
    event DepositProperty(
        uint256 indexed propertyId,
        uint256 liens,
        uint256 max_ltv_ratio,
        uint256 type_id,
        address depositor
    );
    
    event USDXBorrowed(
        uint256 indexed propertyId,
        uint256 value,
        address borrower
    );

    event USDXRepaid(
        uint256 indexed propertyId,
        uint256 value,
        address borrower
    );

    event InterestDeducted(
        uint256 indexed propertyId,
        uint256 value
    );

    event PaymentMissed(
        uint256 indexed propertyId
    );

    event InterestPaymentDeposited(
        uint256 indexed propertyId,
        uint256 value,
        address depositor
    );
    
    event PropertyWithdrawn(
        uint256 indexed propertyId,
        address withdrawer
    );
    
    // Mapping of nft ids to property structs
    mapping(uint256 => Property) private _properties;

    // Next Property ID
    uint256 private _nextPropertyId;
    
    // address of usdx
    USDX private _usdx;

    // Stablecoins that are accepted for repayment
    mapping(IERC20Metadata => IERC20Metadata) private _accepted_stablecoins;
    
    // URI Library
    HelperLibrary _uri_library;
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @param stable_manager Owner that is allowed to mint new properties and receives payment
     * @param usdx Address of USDX token
     * @param uri_library Address of helper library
     */
    function initialize(address stable_manager, USDX usdx, HelperLibrary uri_library) public initializer {
        __Ownable_init(stable_manager);
        __ERC721_init("Stable Property Deposit Manager", "SPD");
        __ERC721Enumerable_init();

        _usdx = usdx;
        _uri_library = uri_library;
    }

    // Core Property Functionality

    /**
     * 
     * called by manager address to deposit the house
     * Normally would be onlyOwner to enforce that only stable
     * can put properties on the chain, this is disabled for now.
     * @param value Value of the property. Denominated in USD with 6 decimals
     * @param liens Value of liens against the property. Denominated in USD with 6 decimals
     * @param max_ltv_ratio Floating point with 9 decimals used as an LTV ratio.
     *  must be less than 1
     * @param type_id category of property (i.e. AG, Commercial, Residential)
     * @param depositor Account that will receive the property NFT
     */
    function depositProperty(
        uint256 value,
        uint256 liens,
        uint256 max_ltv_ratio,
        uint256 type_id,
        address depositor
    ) external returns (uint256 propertyId) {
        require(max_ltv_ratio <= 1e9, "LTV Ratio should be 9 Decimals and less than 1");

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
        _mint(depositor, propertyId);

        ensureDebtHistoryTabulated(propertyId);

        emit DepositProperty(propertyId, liens, max_ltv_ratio, type_id, depositor);
    }

    /**
     * Called by Depositor or Stable to borrow against the property.
     * @param propertyId nft_id of property
     * @param value amount of USDX to mint. 6 decimals
     */
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

        // User should not be able to borrow more than the property is worth,
        // respecting the LTV ratio and current liens
        uint256 new_borrow_amt = property.outstanding_debt + value;
        require(
            new_borrow_amt <= ((property.value - property.outstanding_debt) * property.max_ltv_ratio / 1e9),
            "Borrowing Exceeds Max LTV"
        );
        
        // Make Borrow
        property.outstanding_debt += value;

        // add borrow to events
        Month storage month = property.borrow_history[property.borrow_history.length - 1];
        month.debt_change_events.push(DebtChangeEvent({
            is_borrow: true,
            value: value,
            timestamp: block.timestamp
        }));

        _usdx.mint(msg.sender, value);
        
        emit USDXBorrowed(propertyId, value, msg.sender);
    }

    /**
     * Property owners, or someone on their behalf, can repay the borrow with
     * any accepted stablecoin. Users need to approve the manager to use their
     * stablecoin, even for USDX.
     * @param propertyId nft_id of the property
     * @param stablecoinAddress Address of token that will be used to repay the loan
     * @param payment amount of the stablecoin to repay. Denominated in decimals of the stablecoin
     */
    function repayBorrow(uint256 propertyId, IERC20Metadata stablecoinAddress, uint256 payment) external {
        require(isStablecoinAccepted(stablecoinAddress), "Stablecoin Not Accepted");
        require(propertyId < _nextPropertyId, "Invalid Property ID");

        Property storage property = _properties[propertyId];
        require(!property.is_withdrawn, "Property Already Withdrawn");

        ensureDebtHistoryTabulated(propertyId);

        // Burn USDX, otherwise transfer it to Stable
        if (address(stablecoinAddress) == address(_usdx)) {
            IERC20Metadata(_usdx).safeTransferFrom(msg.sender, address(this), payment);
            _usdx.burn(payment);
        } else {
            stablecoinAddress.safeTransferFrom(msg.sender, owner(), payment);
        }

        uint8 decimals = stablecoinAddress.decimals();
        uint256 normalized_payment = _uri_library.normalizePayment(decimals, payment);
        require(normalized_payment > 0, "Normalized Payment Cannot be Zero");

        require(normalized_payment <= property.outstanding_debt, "Cannot Overpay Debt");

        // Reduce the amount of debt associated with property
        property.outstanding_debt -= normalized_payment;

        // Add borrow to montly borrow history
        Month storage month = property.borrow_history[property.borrow_history.length - 1];
        month.debt_change_events.push(DebtChangeEvent({
            is_borrow: false,
            value: normalized_payment,
            timestamp: block.timestamp
        }));
        
        emit USDXRepaid(propertyId, payment, msg.sender);
    }
    
    /**
     * Property owners can make advance interest payments.
     * @param propertyId nft_id of property
     * @param stablecoinAddress address of stablecoin to repay the debt
     * @param payment value of tokens to transfer. Denominated in decimals
     * of the contract
     */
    function makePayment(uint256 propertyId, IERC20Metadata stablecoinAddress, uint256 payment) external {
        require(isStablecoinAccepted(stablecoinAddress), "Stablecoin Not Accepted");
        require(propertyId < _nextPropertyId, "Invalid Property ID");

        Property storage property = _properties[propertyId];
        require(!property.is_withdrawn, "Property Already Withdrawn");
        
        ensureDebtHistoryTabulated(propertyId);

        // Burn USDX and transfer other tokens to the owner
        if (address(stablecoinAddress) == address(_usdx)) {
            IERC20Metadata(_usdx).safeTransferFrom(msg.sender, address(this), payment);
            _usdx.burn(payment);
        } else {
            stablecoinAddress.safeTransferFrom(msg.sender, owner(), payment);
        }

        uint8 decimals = stablecoinAddress.decimals();
        uint256 normalized_payment = _uri_library.normalizePayment(decimals, payment);
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

        emit InterestPaymentDeposited(propertyId, payment, msg.sender);
    }

    /**
     * if the user has no more debt the property can be withdrawn
     * @param propertyId nft_id of property
     */
    function withdrawProperty(uint256 propertyId) external {
        require(propertyId < _nextPropertyId, "Invalid Property ID");

        Property storage property = _properties[propertyId];
        require(!property.is_withdrawn, "Property Already Withdrawn");

        require(msg.sender == property.depositor, "Only Callable By Depositor");
        require(property.outstanding_debt == 0, "Outstanding Debt must be Zero");
        
        property.is_withdrawn = true;

        emit PropertyWithdrawn(propertyId, msg.sender);
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

    // Only Stable can transfer properties (enforced by onlyOwner modifier)
    function _checkAuthorized(
        address owner, address spender, uint256 tokenId
    ) onlyOwner internal view override {}

    // Utility Functions

    // Takes a payment with a given amount of decimals and associated value
    // and returns the associated value of USDX (6 decimals)
    
    function hasAccountExpired(uint256 propertyId) internal view returns (bool) {
        require(propertyId < _nextPropertyId, "Invalid Property ID");

        Property storage property = _properties[propertyId];

        return _uri_library.diffMonths(property.deposit_timestamp, block.timestamp) > 24;
    }

    function ensureDebtHistoryTabulated(uint256 propertyId) public {
        require(propertyId < _nextPropertyId, "Invalid Property ID");

        Property storage property = _properties[propertyId];
        Month[] storage borrow_history = property.borrow_history;

        uint256 current_month = _uri_library.getCurrentMonth(property.deposit_timestamp);
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
                    month.ending_timestamp = _uri_library.addMonths(property.deposit_timestamp, 1) - 1;
                } else {
                    Month storage last_month = borrow_history[idx - 1];
                    if (!last_month.fully_tabulated) {
                        // fully tabulate last month
                        tabulateMonthlyInterest(propertyId, property, last_month);
                    }
                    Month storage month = borrow_history.push();
                    month.starting_outstanding_debt = last_month.ending_outstanding_debt;
                    month.ending_outstanding_debt = 0;
                    month.interest_owed_for_month = 0;
                    month.fully_tabulated = false;
                    month.starting_timestamp = _uri_library.addMonths(property.deposit_timestamp, idx);
                    month.ending_timestamp = _uri_library.addMonths(property.deposit_timestamp, idx + 1) - 1;
                }
                idx += 1;
            }
        }

        if (has_finished) {
            if (!borrow_history[24].fully_tabulated) {
                // tabulate final month
                tabulateMonthlyInterest(propertyId, property, borrow_history[24]);
            }
        }
    }

    function tabulateMonthlyInterest(uint256 propertyId, Property storage property, Month storage month) internal {
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

        uint256 monthly_interest = dollar_seconds / (month.ending_timestamp - month.starting_timestamp) * rate * denom;

        month.interest_owed_for_month = monthly_interest;
        month.ending_outstanding_debt = amt_borrowed;

        // charge interest
        if (monthly_interest > property.prepaid_interest) {
            property.n_missed_payments += 1;
            property.unpaid_interest += monthly_interest - property.prepaid_interest;
            property.prepaid_interest = 0;
            emit PaymentMissed(propertyId);
        } else {
            property.prepaid_interest -= monthly_interest;
        }
        if (monthly_interest > 0) {
            emit InterestDeducted(propertyId, monthly_interest);
        }

        month.fully_tabulated = true;
    }

    // GETTERS

    function getPropertyInfo(uint256 propertyId) public view returns (PropertyInfo memory) {
        _requireOwned(propertyId);
        Property storage property = _properties[propertyId];

        return PropertyInfo({
            value: property.value,
            outstanding_debt: property.outstanding_debt,
            outstanding_liens: property.outstanding_liens,
            max_ltv_ratio: property.max_ltv_ratio,
            type_id: property.type_id,
            is_withdrawn: property.is_withdrawn,
            depositor: property.depositor,
            deposit_timestamp: property.deposit_timestamp,
            prepaid_interest: property.prepaid_interest,
            unpaid_interest: property.unpaid_interest,
            n_missed_payments: property.n_missed_payments            
        });
    }
    
    function tokenURI(uint256 propertyId) public view override returns (string memory) {
        PropertyInfo memory info = getPropertyInfo(propertyId);
        return _uri_library.tokenURI(propertyId, info);
    }

}
