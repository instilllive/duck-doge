import assert from "node:assert/strict";
import test from "node:test";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { hashTypedData, recoverTypedDataAddress, zeroHash } from "viem";
import { EARNED_SKINS, PAID_SKINS } from "./config.js";
import {
  DOMAIN_TYPEHASH,
  REQUEST_TYPEHASH,
  buildVouchTypedData,
  decodePayload,
  digestVouchRequest,
  encodePayload,
  hashNote,
} from "./payload.js";
import { ownedEntries, selectWornSkin } from "./worn.js";

const CONTRACT = "0x1111111111111111111111111111111111111111";
const VOUCHEE = "0x2222222222222222222222222222222222222222";

function sampleRequest() {
  return {
    vouchee: VOUCHEE,
    kind: 0,
    noteHash: hashNote("met by the river"),
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
  assert.equal(decoded.request.vouchee, VOUCHEE);
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
  assert.equal(REQUEST_TYPEHASH, "0xbec20a566ea3c380327c688353c94b513d0b7cce85c58342c2a61de5a9ceee06");
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
