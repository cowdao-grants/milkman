# Deployment addresses 

The Milkman address is **0x060373D064d0168931dE2AB8DDA7410923d06E88** and it's only available on Mainnet.

For mainnet,
- SushiSwap (UniV2)
    - dynamic slippage price checker: 0x50d03c63344acd9B723243046F680D83D007A2de 
    - fixed (2%) slippage price checker: 0x00e577093BEA1eb273bc497a61E3F2658369b226
    - expected out calculator: 0xd6b20d7d7bdaF450714c26F237a3e5E2418237F1
- Uniswap V2 (UniV2)
    - dynamic slippage price checker: 0x17fb579f14F8Fa9d1daCE1716Fd0E70B952E145b
    - expected out calculator: 0x91aC3CE5b1379933138E20A32a157729C8d28028
- UniV3
    - dynamic slippage price checker: 0x2F965935f93718bB66d53a37a97080785657f0AC
    - expected out calculator: 0xEb80C478f72ac353736be8954eE1aD1B167551F9
- Curve
    - dynamic slippage price checker: 0x39BF89C4fD9A82c262aD9b0434B4dFafCcFD0727
    - expected out calculator: 0x227665A7D708f861b224A372B011447d6172B668
- Chainlink
    - dynamic slippage price checker: 0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c
    - expected out calculator: 0xe23fc134382de3eAF871C249C90bf3Acb846C5ab
- Single-sided Balancer WETH/BAL
    - dynamic slippage price checker: 0xBeA6AAC5bDCe0206A9f909d80a467C93A7D6Da7c
    - expected out calculator: 0xbd0f0A6dcA84cE967336702f875e99D723213849
- Meta 
    - dynamic slippage price checker: 0xf447Bf3CF8582E4DaB9c34C5b261A7b6AD4D6bDD
    - expected out calculator: 0x830f28591CAc072f74721e51B0954539817b14B9
- Hash helper: 0x49Fc95c908902Cf48f5F26ed5ADE284de3b55197
- 'Valid from' price checker decorator: 0x67FE9d6bbeeccb8c7Fe694BE62E08b5fCB5486D7
- FixedMinOutPriceChecker: 0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802

## How to deploy

The Milkman can be deployed and its contract code verified on Etherscan with a dedicated script:

```sh
export ETHERSCAN_API_KEY='your Etherscan API key'
MAINNET_RPC_URL='https://eth.merkle.io'
PK='your ethereum private key here'
forge script 'script/DeployStandaloneMilkman.s.sol:DeployStandaloneMilkman' --rpc-url "$MAINNET_RPC_URL" --private-key "$PK" -vvvv --verify --broadcast
```