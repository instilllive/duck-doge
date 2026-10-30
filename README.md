# duck doge

Testnet-only cosmetic skins for a free-play duck-and-dog dig-run game on DogeOS, Dogecoin's EVM chain. This repository is step 1: the skin contract, its tests, and a deploy script. The game is not in this repo.

`DuckDogeSkins` is an ERC-1155. A mint buys `amount` copies of one shared skin id, which is the quantity a cosmetic shop needs. The valid ids are fixed at deploy as `0 .. skinCount - 1`. `MINT_PRICE` is an immutable constructor argument. The owner can pause minting and can withdraw the full balance. There is no proxy, no upgrade path, no admin mint, and no price setter.

`balancesOf(wallet)` returns one balance per skin id so the game can read which cosmetics a wallet holds. Index `i` is the balance of skin id `i`.

OpenZeppelin Ownable includes `renounceOwnership`. Renouncing would leave the mint fees stuck, because `withdraw` is owner-only. Leave the owner in place.

## Tests

```bash
forge build
forge test -vv
forge coverage --report summary --exclude-tests --no-match-coverage script
```

CI runs `forge build`, `forge test`, and `forge coverage`, then fails if line or branch coverage of `mint`, `pause`, `unpause`, or `withdraw` is below 100%.

## DogeOS Chikyū Testnet

Deploy only to DogeOS Chikyū Testnet, and only from Mark's own throwaway testnet wallet. This repository has no private key, no `.env` secret, and no mainnet RPC.

Official network parameters from the [DogeOS developer quickstart](https://docs.dogeos.com/en/developers/developer-quickstart) and the [wallet setup guide](https://docs.dogeos.com/en/getting-started/user-guide/setup):

| | |
| --- | --- |
| Network | DogeOS Chikyū Testnet |
| RPC URL | `https://rpc.testnet.dogeos.com/` |
| Chain ID | `6281971` (`0x5fdaf3`) |
| Currency | DOGE (18 decimals) |
| Block explorer | `https://dogeos-testnet.l2scan.co` |

Checked on 2026-10-30: `eth_chainId` on `https://rpc.testnet.dogeos.com/` returned `0x5fdaf3`, which is `6281971`.

Testnet DOGE comes from the [DogeOS faucet docs](https://docs.dogeos.com/en/getting-started/user-guide/faucet): [https://faucet.testnet.dogeos.com](https://faucet.testnet.dogeos.com).

The deploy script fixes the testnet configuration: mint price `0.01` DOGE, skin ids `0..7`, and a placeholder metadata URI. Edit those constants in `contracts/script/Deploy.s.sol` before broadcasting if the testnet values should change. They are still constructor arguments, and the deployed contract cannot change them later.

Solidity is `0.8.30` and the EVM target is `prague`, as that quickstart requires.

### Deploy command

Run this locally. The key stays in a Foundry keystore on that machine (`~/.foundry/keystores`), which is outside the repo.

```bash
cast wallet import mark-testnet --interactive

forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url https://rpc.testnet.dogeos.com \
  --chain-id 6281971 \
  --account mark-testnet
```

That simulates the deploy. Add `--broadcast` only when the simulation looks right:

```bash
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url https://rpc.testnet.dogeos.com \
  --chain-id 6281971 \
  --account mark-testnet \
  --broadcast
```

The same script accepts the other CLI signers Foundry supports:

```bash
# Hardware wallet.
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url https://rpc.testnet.dogeos.com \
  --chain-id 6281971 \
  --ledger \
  --broadcast

# Type a key at the prompt. It is not written into the repo.
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url https://rpc.testnet.dogeos.com \
  --chain-id 6281971 \
  --interactive \
  --broadcast
```

`vm.startBroadcast()` uses the account those flags select. Keep the RPC URL and chain id as written above. `--private-key` and a `PRIVATE_KEY` environment variable are not part of this flow.
