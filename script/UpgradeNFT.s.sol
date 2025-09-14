// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import { USDX } from "../src/USDX.sol";
import { StablePropertyDepositManagerV1 } from "../src/StablePropertyDepositManagerV1.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeNFTScript is Script {
    USDX usdx = USDX(0xe022A87655Ac95f32446edDc45724Eb3E79523fB);
    StablePropertyDepositManagerV1 mgr = StablePropertyDepositManagerV1(0x9aF45E84806C90B0b1FcB092CB0026271D329Df5);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("MONAD_PRIVKEY");
        vm.startBroadcast(deployerPrivateKey);
        
        /// @custom:oz-upgrades-unsafe-allow delegatecall
        Upgrades.upgradeProxy(
            address(mgr),
            "StablePropertyDepositManagerV1.sol",
            ""
        );

        vm.stopBroadcast();
    }
}