import {
  concat,
  encodeAbiParameters,
  getAddress,
  isAddress,
  isHex,
  keccak256,
  size,
  toBytes,
  zeroHash,
} from "viem";
import { CHAIN_ID } from "./config.js";

export const PAYLOAD_TYPE = "duck-doge-vouch";
export const DOG_PAYLOAD_TYPE = "duck-doge-dog";
export const DOMAIN_NAME = "DuckDogeVouch";
export const DOMAIN_VERSION = "1";
export const REQUEST_TYPE =
  "VouchRequest(address voucher,address vouchee,uint8 kind,bytes32 noteHash,bytes32 challenge,uint256 nonce,uint256 deadline)";
export const DOMAIN_TYPE =
  "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";

export const REQUEST_TYPEHASH = keccak256(toBytes(REQUEST_TYPE));
export const DOMAIN_TYPEHASH = keccak256(toBytes(DOMAIN_TYPE));

const REQUEST_FIELDS = [
  { name: "voucher", type: "address" },
  { name: "vouchee", type: "address" },
  { name: "kind", type: "uint8" },
  { name: "noteHash", type: "bytes32" },
  { name: "challenge", type: "bytes32" },
  { name: "nonce", type: "uint256" },
  { name: "deadline", type: "uint256" },
];

// Empty and whitespace-only notes hash to zero. The plaintext never goes in the QR.
export function hashNote(note) {
  const text = (note ?? "").trim();
  if (text.length === 0) return zeroHash;
  return keccak256(toBytes(text));
}

export function buildVouchTypedData({ chainId, verifyingContract, request }) {
  return {
    domain: {
      name: DOMAIN_NAME,
      version: DOMAIN_VERSION,
      chainId,
      verifyingContract: getAddress(verifyingContract),
    },
    types: { VouchRequest: REQUEST_FIELDS },
    primaryType: "VouchRequest",
    message: {
      voucher: getAddress(request.voucher),
      vouchee: getAddress(request.vouchee),
      kind: request.kind,
      noteHash: request.noteHash,
      challenge: request.challenge,
      nonce: BigInt(request.nonce),
      deadline: BigInt(request.deadline),
    },
  };
}

// Same bytes EIP-712 and the contract hash. Kept beside viem so the test can compare them.
export function digestVouchRequest(typed) {
  const { domain, message } = typed;
  const structHash = keccak256(
    encodeAbiParameters(
      [
        { type: "bytes32" },
        { type: "address" },
        { type: "address" },
        { type: "uint8" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "uint256" },
        { type: "uint256" },
      ],
      [
        REQUEST_TYPEHASH,
        message.voucher,
        message.vouchee,
        message.kind,
        message.noteHash,
        message.challenge,
        message.nonce,
        message.deadline,
      ],
    ),
  );
  const domainSeparator = keccak256(
    encodeAbiParameters(
      [
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "uint256" },
        { type: "address" },
      ],
      [
        DOMAIN_TYPEHASH,
        keccak256(toBytes(domain.name)),
        keccak256(toBytes(domain.version)),
        BigInt(domain.chainId),
        domain.verifyingContract,
      ],
    ),
  );
  return keccak256(concat(["0x1901", domainSeparator, structHash]));
}

export function encodePayload({ chainId, verifyingContract, request, signature }) {
  return JSON.stringify({
    typ: PAYLOAD_TYPE,
    chainId,
    verifyingContract: getAddress(verifyingContract),
    voucher: getAddress(request.voucher),
    vouchee: getAddress(request.vouchee),
    kind: request.kind,
    noteHash: request.noteHash,
    challenge: request.challenge,
    nonce: BigInt(request.nonce).toString(10),
    deadline: BigInt(request.deadline).toString(10),
    signature,
  });
}

export function decodePayload(text) {
  let raw;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new Error("QR payload is not JSON");
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("QR payload is not an object");
  }
  if (raw.typ !== PAYLOAD_TYPE) throw new Error("QR payload is not a duck doge vouch");
  if (raw.chainId !== CHAIN_ID) throw new Error("QR is not for DogeOS Chikyu testnet");

  const kind = raw.kind;
  if (!Number.isInteger(kind) || kind < 0 || kind > 2) {
    throw new Error("kind must be 0, 1, or 2");
  }
  if (typeof raw.noteHash !== "string" || !isHex(raw.noteHash) || size(raw.noteHash) !== 32) {
    throw new Error("noteHash must be 32 bytes");
  }
  if (typeof raw.challenge !== "string" || !isHex(raw.challenge) || size(raw.challenge) !== 32) {
    throw new Error("challenge must be 32 bytes");
  }
  if (typeof raw.signature !== "string" || !isHex(raw.signature) || size(raw.signature) !== 65) {
    throw new Error("signature must be 65 bytes");
  }

  return {
    chainId: raw.chainId,
    verifyingContract: parseAddress(raw.verifyingContract, "verifyingContract"),
    request: {
      voucher: parseAddress(raw.voucher, "voucher"),
      vouchee: parseAddress(raw.vouchee, "vouchee"),
      kind,
      noteHash: raw.noteHash,
      challenge: raw.challenge,
      nonce: parseUint(raw.nonce, "nonce"),
      deadline: parseUint(raw.deadline, "deadline"),
    },
    signature: raw.signature,
  };
}

function parseAddress(value, label) {
  if (typeof value !== "string" || !isAddress(value, { strict: false })) {
    throw new Error(`${label} is not an address`);
  }
  return getAddress(value);
}

export function encodeDogPayload({ address, challenge }) {
  if (!isHex(challenge) || size(challenge) !== 32) throw new Error("challenge must be 32 bytes");
  return JSON.stringify({
    typ: DOG_PAYLOAD_TYPE,
    chainId: CHAIN_ID,
    address: getAddress(address),
    challenge,
  });
}

export function decodeDogPayload(text) {
  let raw;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new Error("QR payload is not JSON");
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("QR payload is not an object");
  }
  if (raw.typ !== DOG_PAYLOAD_TYPE) throw new Error("QR payload is not a dog challenge");
  if (raw.chainId !== CHAIN_ID) throw new Error("QR is not for DogeOS Chikyu testnet");
  if (typeof raw.challenge !== "string" || !isHex(raw.challenge) || size(raw.challenge) !== 32) {
    throw new Error("challenge must be 32 bytes");
  }
  return {
    chainId: raw.chainId,
    address: parseAddress(raw.address, "address"),
    challenge: raw.challenge,
  };
}

// Keep challenges the dog has shown inside the same window the contract allows.
export function rememberChallenges(previous, challenge, nowMs, ttlMs) {
  const live = previous.filter((item) => nowMs - item.at <= ttlMs && item.challenge !== challenge);
  live.push({ challenge, at: nowMs });
  return live;
}

export function challengeIsLive(list, challenge, nowMs, ttlMs) {
  const wanted = challenge.toLowerCase();
  return list.some((item) => item.challenge.toLowerCase() === wanted && nowMs - item.at <= ttlMs);
}

function parseUint(value, label) {
  if (typeof value !== "string" || !/^[0-9]+$/.test(value)) {
    throw new Error(`${label} must be a decimal string`);
  }
  return BigInt(value);
}
