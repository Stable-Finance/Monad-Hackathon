## Readme

### Addresses:

USDX: `0xD875Ba8e2caD3c0f7e2973277C360C8d2f92B510`
StablePropertyDepositManager: `0x9d380F07463900767A8cB26A238CEf047A174D62`

### Deploy:

Load privkey into `MONAD_TESTNET` acc: `cast wallet import MONAD_TESTNET --private-key 0xyourprivkey`
Deploy: `forge clean && forge script ./script/Deploy.s.sol --rpc-url https://testnet-rpc.monad.xyz/ --broadcast --account MONAD_TESTNET --via-ir`
Redeploy NFT: `forge clean && forge script ./script/DeployNFT.s.sol --rpc-url https://testnet-rpc.monad.xyz/ --broadcast --account MONAD_TESTNET --via-ir`

### Tests

`forge clean && forge test --via-ir`


```
Ran 6 tests for test/StablePropertyDepositManager.sol:StablePropertyDepositManagerTest
[PASS] test_GetCurrentMonth() (gas: 106689)
[PASS] test_IntegrationOne() (gas: 1105941)
[PASS] test_NFTsEnumerable() (gas: 1120162)
[PASS] test_NFTsSoulbound() (gas: 382872)
[PASS] test_NormalizePayment() (gas: 26503)
[PASS] test_TokenURI() (gas: 688838)
Suite result: ok. 6 passed; 0 failed; 0 skipped; finished in 2.24s (6.40ms CPU time)

Ran 1 test suite in 2.24s (2.24s CPU time): 6 tests passed, 0 failed, 0 skipped (6 total tests)
```