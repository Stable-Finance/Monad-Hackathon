// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import { USDX } from "../src/USDX.sol";
import { StablePropertyDepositManager } from "../src/StablePropertyDepositManager.sol";
import { MockUSDT } from "./MockUSDT.sol";

contract StablePropertyDepositManagerHarness is StablePropertyDepositManager {
    constructor(address stable_manager_, USDX usdx) StablePropertyDepositManager(stable_manager_, usdx) {}
    
    function getCurrentMonthHarness(uint256 starting_timestamp) external view returns (uint256) {
        return super.getCurrentMonth(starting_timestamp);
    }
}

contract StablePropertyDepositManagerTest is Test {
    USDX public usdx;
    StablePropertyDepositManagerHarness public manager;
    MockUSDT public usdt;

    address owner      = 0x00b10AD612DC42AAb9968d3bAe57d55fe349DfBD;
    address depositor1 = 0x011945a4AadBE36c339F66fd89D233268CDf5668;

    function setUp() public {
        vm.startPrank(owner);
        usdx = new USDX(owner);
        manager = new StablePropertyDepositManagerHarness(owner, usdx);
        usdx.transferOwnership(address(manager));
        
        usdt = new MockUSDT(1e20 * 1e8);
        
        manager.addAcceptedStablecoin(usdt);
        usdt.transfer(depositor1, 1e19);
        vm.stopPrank();
    }

    function test_IntegrationOne() public {
        vm.prank(owner);
        console.logAddress(msg.sender);
        uint256 propertyId = manager.depositProperty(
            1000000 * 1000000,
            0,
            0.8e9,
            0,
            depositor1
        );
        assertEq(propertyId, 0);

        vm.prank(depositor1);
        manager.borrow(0, 10 * 1e6);
        vm.prank(depositor1);
        uint256 minted = usdx.balanceOf(depositor1);
        assertEq(minted, 10 * 1e6);
        
        // ff 40 days
        skip(60 * 60 * 24 * 40);
        
        vm.prank(owner);
        manager.ensureDebtHistoryTabulated(propertyId);
    }

    function testGetCurrentMonth() public {
        uint256 startTime = 1741645302; // 3:22 PM on Mar 10 Mountain Time 2025
        vm.warp(startTime);
        // start on month 0
        assertEq(manager.getCurrentMonthHarness(startTime), 0);
        
        // ff 21 days to Mar 31, should be month 0
        skip(60 * 60 * 24 * 21);
        assertEq(manager.getCurrentMonthHarness(startTime), 0);

        // ff 1 days to Apr 1, should be month 1
        skip(60 * 60 * 24 * 16);
        assertEq(manager.getCurrentMonthHarness(startTime), 1);
        
        // ff 334 days to Mar 1 2026, should be month 12
        skip(60 * 60 * 24 * 334);
        assertEq(manager.getCurrentMonthHarness(startTime), 12);
    }
}
