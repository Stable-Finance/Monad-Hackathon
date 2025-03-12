// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import { USDX } from "../src/USDX.sol";
import { URILibrary } from "../src/URILibrary.sol";
import { StablePropertyDepositManagerHarness } from "../src/mocks/StablePropertyDepositManagerHarness.sol";
import { StablePropertyDepositManagerV1 } from "../src/StablePropertyDepositManagerV1.sol";
import { MockUSDT } from "../src/mocks/MockUSDT.sol";

import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";



contract StablePropertyDepositManagerTest is Test {
    USDX public usdx;
    URILibrary public uri_library;
    StablePropertyDepositManagerHarness public manager;
    MockUSDT public usdt;

    address owner      = 0x00b10AD612DC42AAb9968d3bAe57d55fe349DfBD;
    address depositor1 = 0x011945a4AadBE36c339F66fd89D233268CDf5668;
    address depositor2 = 0x029312b2A3aAc8C6abB7F59Af62a20B134857da3;

    function setUp() public {
        vm.startPrank(owner);
        usdx = USDX(Upgrades.deployTransparentProxy(
            "USDX.sol",
            owner,
            abi.encodeCall(USDX.initialize, (owner))
        ));

        uri_library = new URILibrary();

        manager = StablePropertyDepositManagerHarness(Upgrades.deployTransparentProxy(
            "StablePropertyDepositManagerHarness.sol",
            owner,
            abi.encodeCall(StablePropertyDepositManagerV1.initialize, (owner, usdx, uri_library))
        ));
        usdx.grantRole(keccak256("MINTER"), address(manager));
        
        usdt = new MockUSDT(1e20 * 1e8);
        
        manager.addAcceptedStablecoin(usdt);
        usdt.transfer(depositor1, 1e19);
        vm.stopPrank();
    }

    function test_IntegrationOne() public {
        vm.prank(owner);
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

    function test_GetCurrentMonth() public {
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

    function test_TokenURI() public {
        vm.prank(owner);
        uint256 propertyId = manager.depositProperty(
            1000000 * 1000000,
            0,
            0.8e9,
            0,
            depositor1
        );
        assertEq(propertyId, 0);
        
        string memory metadata = manager.tokenURI(propertyId);

        // Its OK and expected to change this number whenever changing the
        // metadata format. Just make sure the json and svg formatting is valid
        // when doing so.
        assertEq(bytes(metadata).length, 2461);
    }

    function test_NFTsSoulbound() public {
        vm.prank(owner);
        uint256 propertyId = manager.depositProperty(
            1000000 * 1000000,
            0,
            0.8e9,
            0,
            depositor1
        );
        assertEq(propertyId, 0);
        
        vm.prank(depositor1);
        vm.expectRevert();
        manager.transferFrom(depositor1, depositor2, propertyId);
    }

    function test_NFTsEnumerable() public {
        vm.prank(owner);
        uint256 propertyId = manager.depositProperty(
            1000000 * 1000000,
            0,
            0.8e9,
            0,
            depositor1
        );
        assertEq(propertyId, 0);
        vm.prank(owner);
        uint256 propertyId2 = manager.depositProperty(
            1000000 * 1000000,
            0,
            0.8e9,
            0,
            owner
        );
        assertEq(propertyId2, 1);
        vm.prank(owner);
        uint256 propertyId3 = manager.depositProperty(
            1000000 * 1000000,
            0,
            0.8e9,
            0,
            depositor1
        );
        assertEq(propertyId3, 2);
        
        assertEq(manager.tokenOfOwnerByIndex(depositor1, 0), 0);
        assertEq(manager.tokenOfOwnerByIndex(depositor1, 1), 2);
        assertEq(manager.balanceOf(depositor1), 2);
    }
}
