## Readme

Load privkey into `MONAD_TESTNET` acc: `cast wallet import MONAD_TESTNET --private-key 0xyourprivkey`
Deploy: `forge clean && forge script ./script/Deploy.s.sol --rpc-url https://testnet-rpc.monad.xyz/ --broadcast --account MONAD_TESTNET --via-ir`
Test: `forge clean && forge test --via-ir`


### Addresses:

USDX: `0xD875Ba8e2caD3c0f7e2973277C360C8d2f92B510`
StablePropertyDepositManager: `0x331920dff45e579addf26d9bb4b9182e0612daf0`