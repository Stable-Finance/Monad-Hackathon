// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import { USDX } from "../src/USDX.sol";
import { HelperLibrary } from "../src/HelperLibrary.sol";
import { StablePropertyDepositManagerV1 } from "../src/StablePropertyDepositManagerV1.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("MONAD_PRIVKEY");
        vm.startBroadcast(deployerPrivateKey);

        
        USDX usdx = USDX(Upgrades.deployTransparentProxy(
            "USDX.sol",
            vm.addr(deployerPrivateKey),
            abi.encodeCall(USDX.initialize, (vm.addr(deployerPrivateKey)))
        ));

        HelperLibrary lib = new HelperLibrary();

        StablePropertyDepositManagerV1 deposit_mgr = StablePropertyDepositManagerV1(Upgrades.deployTransparentProxy(
            "StablePropertyDepositManager.sol",
            vm.addr(deployerPrivateKey),
            abi.encodeCall(StablePropertyDepositManagerV1.initialize, (vm.addr(deployerPrivateKey), usdx, lib))
        ));

        usdx.grantRole(keccak256("MINTER"), address(deposit_mgr));

        console.logAddress(address(usdx));

        vm.stopBroadcast();
    }
}
