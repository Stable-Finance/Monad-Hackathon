// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {USDX} from "../src/USDX.sol";
import { StablePropertyDepositManager } from "../src/StablePropertyDepositManager.sol";

contract DeployScript is Script {
    USDX public usdx;
    StablePropertyDepositManager public deposit;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("MONAD_PRIVKEY");
        vm.startBroadcast(deployerPrivateKey);

        usdx = new USDX(vm.addr(deployerPrivateKey));
        deposit = new StablePropertyDepositManager(vm.addr(deployerPrivateKey), usdx);
        usdx.transferOwnership(address(deposit));

        console.logAddress(address(usdx));

        vm.stopBroadcast();
    }
}
