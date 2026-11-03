import assert from "node:assert/strict";
import test from "node:test";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { hashTypedData, recoverTypedDataAddress, zeroHash } from "viem";
import { EARNED_SKINS, PAID_SKINS } from "./config.js";
import {
  DOMAIN_TYPEHASH,
  REQUEST_TYPEHASH,
  buildVouchTypedData,
  challengeIsLive,
  decodeDogPayload,
  decodePayload,
  digestVouchRequest,
  encodeDogPayload,
  encodePayload,
  hashNote,
  rememberChallenges,
} from "./payload.js";
import { ownedEntries, selectWornSkin } from "./worn.js";

const CONTRACT = "0x1111111111111111111111111111111111111111";
const VOUCHEE = "0x2222222222222222222222222222222222222222";
const DOG = "0x3333333333333333333333333333333333333333";
const CHALLENGE = `0x${"ab".repeat(32)}`;

function sampleRequest() {
  return {
    voucher: DOG,
    vouchee: VOUCHEE,
    kind: 0,
    noteHash: hashNote("met by the river"),
    challenge: CHALLENGE,
    nonce: (1n << 200n) + 123n,
    deadline: 1_700_000_060n,
  };
}

test("note hash is zero for a blank note and keccak256 otherwise", () => {
  assert.equal(hashNote(""), zeroHash);
  assert.equal(hashNote("   "), zeroHash);
  assert.equal(hashNote(undefined), zeroHash);
  assert.equal(hashNote("met by the river"), sampleRequest().noteHash);
  assert.notEqual(hashNote("met by the river"), zeroHash);
});

test("QR payload round-trips the signed request", () => {
  const request = sampleRequest();
  const signature = `0x${"ab".repeat(65)}`;
  const decoded = decodePayload(
    encodePayload({ chainId: 6281971, verifyingContract: CONTRACT, request, signature }),
  );

  assert.equal(decoded.chainId, 6281971);
  assert.equal(decoded.verifyingContract, CONTRACT);
  assert.equal(decoded.request.voucher, DOG);
  assert.equal(decoded.request.vouchee, VOUCHEE);
  assert.equal(decoded.request.challenge, CHALLENGE);
  assert.equal(decoded.request.kind, 0);
  assert.equal(decoded.request.noteHash, request.noteHash);
  assert.equal(decoded.request.nonce, request.nonce);
  assert.equal(decoded.request.deadline, request.deadline);
  assert.equal(decoded.signature, signature);
});

test("QR payload rejects a relay onto another chain or a broken signature", () => {
  const request = sampleRequest();
  const signature = `0x${"ab".repeat(65)}`;
  const encoded = encodePayload({
    chainId: 6281971,
    verifyingContract: CONTRACT,
    request,
    signature,
  });
  const parsed = JSON.parse(encoded);

  assert.throws(() => decodePayload(JSON.stringify({ ...parsed, chainId: 1 })), /Chikyu testnet/);
  assert.throws(() => decodePayload(JSON.stringify({ ...parsed, kind: "0" })), /kind/);
  assert.throws(() => decodePayload(JSON.stringify({ ...parsed, signature: "0xabcd" })), /signature/);
  assert.throws(() => decodePayload("{"), /JSON/);
  assert.throws(() => decodePayload(JSON.stringify({ ...parsed, typ: "other" })), /not a duck doge vouch/);
});

test("typed-data signature recovers the duck and matches the manual digest", async () => {
  assert.equal(REQUEST_TYPEHASH, "0x60f1dc9a4de03de354ecbaa3c1266478f991ad6a8ec7874e71579ec30de8aa72");
  assert.equal(DOMAIN_TYPEHASH, "0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f");

  const account = privateKeyToAccount(generatePrivateKey());
  const request = { ...sampleRequest(), vouchee: account.address, kind: 1, noteHash: zeroHash };
  const typed = buildVouchTypedData({
    chainId: 6281971,
    verifyingContract: CONTRACT,
    request,
  });

  assert.equal(digestVouchRequest(typed), hashTypedData(typed));

  const signature = await account.signTypedData(typed);
  const recovered = await recoverTypedDataAddress({ ...typed, signature });
  assert.equal(recovered, account.address);

  const decoded = decodePayload(
    encodePayload({ chainId: 6281971, verifyingContract: CONTRACT, request, signature }),
  );
  const again = buildVouchTypedData({
    chainId: decoded.chainId,
    verifyingContract: decoded.verifyingContract,
    request: decoded.request,
  });
  assert.equal(await recoverTypedDataAddress({ ...again, signature: decoded.signature }), account.address);
});

test("profile wears the first earned skin, then a shop skin", () => {
  const earnedFirst = selectWornSkin([0n, 2n], [0n, 1n], PAID_SKINS, EARNED_SKINS);
  assert.equal(earnedFirst.source, "Earned");
  assert.equal(earnedFirst.name, "Ribbon");
  assert.equal(earnedFirst.balance, 1n);

  const shopOnly = selectWornSkin([0n, 4n], [0n, 0n], PAID_SKINS, EARNED_SKINS);
  assert.equal(shopOnly.source, "Shop");
  assert.equal(shopOnly.name, "Gold");

  assert.equal(selectWornSkin([0n], [0n], PAID_SKINS, EARNED_SKINS), null);

  const extra = ownedEntries([0n, 3n], [], "Earned");
  assert.equal(extra[0].name, "Earned 1");
  assert.equal(extra[0].balance, 3n);
});

test("dog QR round-trips the address and challenge", () => {
  const decoded = decodeDogPayload(encodeDogPayload({ address: DOG.toLowerCase(), challenge: CHALLENGE }));
  assert.equal(decoded.address, DOG);
  assert.equal(decoded.challenge, CHALLENGE);
  assert.equal(decoded.chainId, 6281971);
  assert.throws(() => decodeDogPayload(encodePayload({
    chainId: 6281971,
    verifyingContract: CONTRACT,
    request: sampleRequest(),
    signature: `0x${"ab".repeat(65)}`,
  })), /dog challenge/);
});

test("a dog challenge stays live for the short window and then goes stale", () => {
  const ttl = 20_000;
  const now = 1_000_000;
  const older = `0x${"11".repeat(32)}`;
  let live = rememberChallenges([], CHALLENGE, now, ttl);
  live = rememberChallenges(live, older, now + 5_000, ttl);
  assert.equal(challengeIsLive(live, CHALLENGE, now + 5_000, ttl), true);
  assert.equal(challengeIsLive(live, older, now + 5_000, ttl), true);
  assert.equal(challengeIsLive(live, CHALLENGE, now + ttl, ttl), true);
  assert.equal(challengeIsLive(live, CHALLENGE, now + ttl + 1, ttl), false);
  assert.equal(challengeIsLive(live, older, now + 5_000 + ttl, ttl), true);
  assert.equal(challengeIsLive(live, `0x${"22".repeat(32)}`, now + 5_000, ttl), false);
});
