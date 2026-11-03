# duck doge

Testnet-only cosmetics and in-person vouches for a duck-and-dog game on DogeOS, Dogecoin's EVM chain. Skins are an ERC-1155. A vouch is not a token: the duck signs a short request, the dog submits it, and the contract records the pair.

This repository does not contain the game. It has the two contracts, their tests, a deploy script, and a small page for signing and scanning.

## Skins

`DuckDogeSkins` sells paid skins and mints earned skins.

Paid ids are `0 .. skinCount - 1`. `mint(skinId, amount)` charges `MINT_PRICE * amount`. `MINT_PRICE` and the paid id set are fixed in the constructor. The owner can pause paid mints and can withdraw the full balance. There is no proxy, no upgrade path, no admin mint of paid skins, and no price setter.

Earned ids are `skinCount .. skinCount + earnedSkinCount - 1`. Index `0` is token id `skinCount`. `mintEarned(to, earnedIndex)` mints one of those ids for free. Only `minter` may call it. `setMinter` is owner-only and works once: a second call reverts, and the owner cannot mint earned skins unless the minter was set to the owner. The deploy script sets the minter to `DuckDogeVouch` and does not change it again. Earned mints ignore `pause`, so the owner cannot freeze new vouches by pausing the shop.

`balancesOf(wallet)` returns one balance per paid id. `earnedBalancesOf(wallet)` returns one balance per earned index. Earned skins transfer with the normal ERC-1155 functions.

OpenZeppelin Ownable includes `renounceOwnership`. Renouncing would leave the paid-mint fees stuck, because `withdraw` is owner-only. Leave the owner in place. Renouncing does not clear the minter.

## Vouches

`DuckDogeVouch` records that one wallet vouches for another. There is no transfer function, no proxy, no upgrade path, no `delegatecall`, no `selfdestruct`, and no owner. Paid skins are not read. Holding a shop skin does not change whether a vouch succeeds.

The duck is the person asking. The dog is the person vouching.

1. The duck signs an EIP-712 `VouchRequest` `{vouchee, kind, noteHash, nonce, deadline}`. `kind` is `MetInPerson` (0), `WorkedWith` (1), or `KnowsWell` (2). `noteHash` may be zero. The page uses a 60 second deadline.
2. The duck shows that signed request as a QR code.
3. The dog scans it and submits `vouch(request, voucheeSignature)` from the dog's own wallet.

The contract accepts the request only when all of these hold:

- `deadline` has not passed, and `deadline <= block.timestamp + 90 seconds`. The extra 30 seconds past the 60 second QR is inclusion slack.
- The signature recovers to `vouchee` for this contract and chain.
- `msg.sender` is not `vouchee`.
- The nonce has not been used by that vouchee.
- The dog does not already have an active vouch for that duck.
- The dog has created fewer than 3 vouches in the current epoch week.

The first successful vouch for a pair mints one earned skin to the duck. The index is `lifetimeReceived % earnedSkinCount`, then the lifetime counter increments. Lifetime counts first-time pairs only, so the ids cycle as more distinct dogs vouch for the same duck. A revoked pair can be vouched again, but that second vouch does not mint another skin.

### Weekly limit

An epoch week is `block.timestamp / 7 days`. Week `n` is `[n * 7 days, (n + 1) * 7 days)`. Each voucher may create 3 vouches in an epoch. The next epoch starts the count at 0. This is not a rolling 7-day window: a voucher can create 3 at the end of one epoch and 3 at the start of the next. Revoking does not give the slot back. Week 0 is a real epoch. A stored epoch of 0 is not treated as "unset", so the cap applies there too.

The cap, plus one earned skin per pair ever, is what limits farming. A dog cannot mint a second skin for the same duck by revoking and vouching again, and cannot mint for more than three new ducks in an epoch.

### Revoke does not burn the skin

`revoke(vouchee)` succeeds only for the dog who created that active vouch. The record stays readable through `getVouch` with `active` false, and it stops adding to `activeVouchCount`. `activeVouchCount(address)` is how many active vouches that address has received.

The earned skin stays. It is an ordinary transferable ERC-1155. The duck may already have sent it to someone else. Burning from the vouch contract would either revert the revoke when the token has moved, which would trap the dog, or require an approval the contract does not have. Leaving the cosmetic in place is the safer behavior. The vouch count is the thing revoke changes. The skin remains a souvenir of the first vouch for that pair.

### Co-presence

The QR and the short deadline are a weak co-presence check. A scanned code can be relayed, and the signature does not name the dog, so the first wallet to submit a still-valid payload is stored as the voucher. That is the accepted testnet tradeoff. This is not proof that two humans met.

## Tests

```bash
forge build
forge test -vv
forge coverage --report summary --exclude-tests --no-match-coverage script
```

CI runs `forge build`, `forge test`, and `forge coverage`. It fails if line or branch coverage of the skins contract drops below 100%, including `mint`, `pause`, `unpause`, `withdraw`, `setMinter`, `mintEarned`, and `earnedBalancesOf`. It also fails if `vouch`, `revoke`, `enforceWeeklyLimit`, or the rest of `DuckDogeVouch.sol` drops below 100%.

The page has its own tests:

```bash
cd web
npm ci
npm test
npm run build
```

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

Solidity is `0.8.30` and the EVM target is `prague`, as that quickstart requires.

### Deploy command

Run this locally. The key stays in a Foundry keystore on that machine (`~/.foundry/keystores`), which is outside the repo. The script deploys `DuckDogeSkins` (paid ids `0..7`, earned ids `8..11`, price `0.01` DOGE) and `DuckDogeVouch`, then calls `setMinter` once with the vouch contract. The broadcaster becomes the skins owner. The script reverts unless the chain id is `6281971`.

```bash
cast wallet import mark-testnet --interactive

forge script contracts/script/DeployVouch.s.sol:DeployVouch \
  --rpc-url https://rpc.testnet.dogeos.com \
  --chain-id 6281971 \
  --account mark-testnet
```

That simulates the deploy. Add `--broadcast` only when the simulation looks right:

```bash
forge script contracts/script/DeployVouch.s.sol:DeployVouch \
  --rpc-url https://rpc.testnet.dogeos.com \
  --chain-id 6281971 \
  --account mark-testnet \
  --broadcast
```

The same script accepts the other CLI signers Foundry supports:

```bash
# Hardware wallet.
forge script contracts/script/DeployVouch.s.sol:DeployVouch \
  --rpc-url https://rpc.testnet.dogeos.com \
  --chain-id 6281971 \
  --ledger \
  --broadcast

# Type a key at the prompt. It is not written into the repo.
forge script contracts/script/DeployVouch.s.sol:DeployVouch \
  --rpc-url https://rpc.testnet.dogeos.com \
  --chain-id 6281971 \
  --interactive \
  --broadcast
```

`vm.startBroadcast()` uses the account those flags select. Keep the RPC URL and chain id as written above. `--private-key` and a `PRIVATE_KEY` environment variable are not part of this flow.

Paste the two logged addresses into `web/src/config.js` as `skinsAddress` and `vouchAddress`. Until those are filled in, the page will not send transactions.

`contracts/script/Deploy.s.sol` still deploys skins alone and leaves `minter` unset, so earned mints stay closed. Use `DeployVouch` for the linked pair. Running both deploys two skins contracts.

## Web

`web/` is a static Vite page. Duck mode connects an injected wallet (MyDoge or MetaMask), picks a kind, optionally types a note, signs the EIP-712 request, and shows a QR that counts down from 60 seconds. Dog mode scans that QR with the camera, or accepts a paste when the browser has no camera, shows the vouchee and the kind, and submits `vouch`. Profile reads `activeVouchCount`, `balancesOf`, and `earnedBalancesOf` for any address. The duck and dog drawings wear the first earned skin that address holds, otherwise the first shop skin.

```bash
cd web
npm ci
npm run dev
```

Open the printed local URL and switch the wallet to DogeOS Chikyū Testnet.
