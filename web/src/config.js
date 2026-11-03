// DogeOS Chikyū testnet only. Replace the zero addresses after Mark deploys.
export const CHAIN_ID = 6281971;
export const CHAIN_ID_HEX = "0x5fdaf3";
export const RPC_URL = "https://rpc.testnet.dogeos.com/";
export const EXPLORER_URL = "https://dogeos-testnet.l2scan.co";
export const REQUEST_SECONDS = 15;
export const ROTATE_MS = 5000;
export const CHALLENGE_TTL_MS = 20000;

export const vouchAddress = "0x0000000000000000000000000000000000000000";
export const skinsAddress = "0x0000000000000000000000000000000000000000";

export const KINDS = [
  { id: 0, name: "Met in person" },
  { id: 1, name: "Worked with" },
  { id: 2, name: "Knows well" },
];

// Display names for the testnet deployment: paid ids 0..7, earned indexes 0..3.
// The chain is the source of balances. These labels are not stored on-chain.
export const PAID_SKINS = [
  { name: "Plain", color: "#e6b325" },
  { name: "Gold", color: "#c48a12" },
  { name: "Teal", color: "#2a9d8f" },
  { name: "Berry", color: "#9b2226" },
  { name: "Ink", color: "#1d3557" },
  { name: "Moss", color: "#606c38" },
  { name: "Lilac", color: "#6d597a" },
  { name: "Ember", color: "#ee6c4d" },
];

export const EARNED_SKINS = [
  { name: "Paw", color: "#d97706" },
  { name: "Ribbon", color: "#be123c" },
  { name: "Bandana", color: "#0369a1" },
  { name: "Scarf", color: "#4d7c0f" },
];
