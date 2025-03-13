// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@BokkyPooBahsDateTimeLibrary/BokkyPooBahsDateTimeLibrary.sol";

import { PropertyInfo, DebtChangeEvent, Month, Property } from "./IStablePropertyDepositManagerV1.sol";

contract URILibrary {
    using Strings for uint256;

    function tokenURI(uint256 propertyId, PropertyInfo memory info) external pure returns (string memory) {
        bytes memory dataURI = abi.encodePacked(
            '{',
                '"name": "Stable Property #', propertyId.toString(), '",',
                '"description": "Properties Deposited into Stable",',
                '"image": "', generateSVG(propertyId, info), '",',
                '"attributes": [',
                    '{',
                        '"trait_type": "Value",',
                        '"display_type": "number",',
                        '"value":', (info.value / 1000000).toString(),
                    '},',
                    '{',
                        '"trait_type": "Leins",',
                        '"display_type": "number",',
                        '"value":', (info.outstanding_liens / 1000000).toString(),
                    '},',
                    '{',
                        '"trait_type": "Outstanding Debt",',
                        '"display_type": "number",',
                        '"value":', (info.outstanding_debt / 1000000).toString(),
                    '},',
                    '{',
                        '"trait_type": "Max LTV%",',
                        '"display_type": "number",',
                        '"value":', (info.max_ltv_ratio / 10000000).toString(),
                    '},',
                    '{',
                        '"trait_type": "Type ID",',
                        '"display_type": "number",',
                        '"value":', info.type_id.toString(),
                    '},',
                    '{',
                        '"trait_type": "Is Withdrawn",',
                        '"value": "', info.is_withdrawn ? "Yes" : "No", '"',
                    '},',
                    '{',
                        '"trait_type": "Depositor",',
                        '"value": "', Strings.toHexString(uint160(info.depositor), 20), '"',
                    '},',
                    '{',
                        '"trait_type": "Deposit Timestamp",',
                        '"display_type": "date",',
                        '"value":', info.deposit_timestamp.toString(),
                    '},',
                    '{',
                        '"trait_type": "Prepaid Interest",',
                        '"display_type": "number",',
                        '"value":', (info.prepaid_interest / 1000000).toString(),
                    '},',
                    '{',
                        '"trait_type": "Unpaid Interest",',
                        '"display_type": "number",',
                        '"value":', (info.unpaid_interest / 1000000).toString(),
                    '},',
                    '{',
                        '"trait_type": "Num Missed Payments",',
                        '"display_type": "number",',
                        '"value":', uint256(info.n_missed_payments).toString(),
                    '}',
                ']',
            '}'
        );
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(dataURI)
            )
        );
    }

    function generateSVG(uint256 propertyId, PropertyInfo memory info) internal pure returns (string memory) {

        bytes memory svg = abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350">',
            '<style>.base { fill: white; font-family: serif; font-size: 14px; }</style>',
            '<rect width="100%" height="100%" fill="black" />',
            '<text x="5%" y="30%" class="base" dominant-baseline="middle" text-anchor="start">',"Property #",propertyId.toString(),'</text>',
            '<text x="5%" y="40%" class="base" dominant-baseline="middle" text-anchor="start">', "Value: ",(info.value / 1000000).toString(),'</text>',
            '<text x="5%" y="50%" class="base" dominant-baseline="middle" text-anchor="start">', "Liens: ",(info.outstanding_liens / 1000000).toString(),'</text>',
            '<text x="5%" y="60%" class="base" dominant-baseline="middle" text-anchor="start">', "Max LTV %: ",(info.max_ltv_ratio / 10000000).toString(),'</text>',
            '<text x="5%" y="70%" class="base" dominant-baseline="middle" text-anchor="start">', "Borrowed: ",(info.outstanding_debt / 1000000).toString(),'</text>',
            '</svg>'
        );
        return string(
            abi.encodePacked(
                "data:image/svg+xml;base64,",
                Base64.encode(svg)
            )    
        );
    }

    function normalizePayment(uint8 decimals, uint256 value) external pure returns (uint256) {
        if (decimals >= 6) {
            return value * (10 ** (decimals - 6));
        } else {
            return value / (10 ** (6 - decimals));
        }
    }

    function getCurrentMonth(uint256 starting_timestamp) external view returns (uint256) {
        return BokkyPooBahsDateTimeLibrary.diffMonths(starting_timestamp, block.timestamp);
    }

    function addMonths(uint256 timestamp, uint256 n_months) external pure returns (uint256) {
        return BokkyPooBahsDateTimeLibrary.addMonths(timestamp, n_months);
    }

    function diffMonths(uint256 start_timestamp, uint256 end_timestamp) external pure returns (uint256) {
        return BokkyPooBahsDateTimeLibrary.diffMonths(start_timestamp, end_timestamp);
    }
}