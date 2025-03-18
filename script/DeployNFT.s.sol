// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import { USDX } from "../src/USDX.sol";
import { HelperLibrary } from "../src/HelperLibrary.sol";
import { StablePropertyDepositManagerV1 } from "../src/StablePropertyDepositManagerV1.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract DeployScript is Script {
    function setUp() public {}
    USDX usdx = USDX(0xD875Ba8e2caD3c0f7e2973277C360C8d2f92B510);
    
    IERC20Metadata usdt = IERC20Metadata(0x88b8E2161DEDC77EF4ab7585569D2415a1C1055D);
    IERC20Metadata usdc = IERC20Metadata(0xf817257fed379853cDe0fa4F97AB987181B1E5Ea);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("MONAD_PRIVKEY");
        vm.startBroadcast(deployerPrivateKey);

        HelperLibrary lib = new HelperLibrary();

        StablePropertyDepositManagerV1 deposit_mgr = StablePropertyDepositManagerV1(Upgrades.deployTransparentProxy(
            "StablePropertyDepositManagerV1.sol",
            vm.addr(deployerPrivateKey),
            abi.encodeCall(StablePropertyDepositManagerV1.initialize, (vm.addr(deployerPrivateKey), usdx, lib))
        ));
        console.log("Deposit Manager:");
        console.logAddress(address(deposit_mgr));

        deposit_mgr.addAcceptedStablecoin(usdt);
        deposit_mgr.addAcceptedStablecoin(usdc);

        usdx.grantRole(keccak256("MINTER"), address(deposit_mgr));

        vm.stopBroadcast();
    }
}
