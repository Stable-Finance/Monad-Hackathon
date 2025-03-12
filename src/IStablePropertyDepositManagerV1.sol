// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

struct PropertyInfo {
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
}

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