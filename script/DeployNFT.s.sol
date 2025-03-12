// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import { USDX } from "../src/USDX.sol";
import { URILibrary } from "../src/URILibrary.sol";
import { StablePropertyDepositManagerV1 } from "../src/StablePropertyDepositManagerV1.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployScript is Script {
    function setUp() public {}
    USDX usdx = USDX(0xD875Ba8e2caD3c0f7e2973277C360C8d2f92B510);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("MONAD_PRIVKEY");
        vm.startBroadcast(deployerPrivateKey);

        URILibrary lib = new URILibrary();

        StablePropertyDepositManagerV1 deposit_mgr = StablePropertyDepositManagerV1(Upgrades.deployTransparentProxy(
            "StablePropertyDepositManagerV1.sol",
            vm.addr(deployerPrivateKey),
            abi.encodeCall(StablePropertyDepositManagerV1.initialize, (vm.addr(deployerPrivateKey), usdx, lib))
        ));

        usdx.grantRole(keccak256("MINTER"), address(deposit_mgr));

        console.logAddress(address(usdx));

        vm.stopBroadcast();
    }
}
