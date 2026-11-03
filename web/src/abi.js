export const vouchAbi = [
  {
    type: "function",
    name: "vouch",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "request",
        type: "tuple",
        components: [
          { name: "voucher", type: "address" },
          { name: "vouchee", type: "address" },
          { name: "kind", type: "uint8" },
          { name: "noteHash", type: "bytes32" },
          { name: "challenge", type: "bytes32" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" },
        ],
      },
      { name: "voucheeSignature", type: "bytes" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "revoke",
    stateMutability: "nonpayable",
    inputs: [{ name: "vouchee", type: "address" }],
    outputs: [],
  },
  {
    type: "function",
    name: "activeVouchCount",
    stateMutability: "view",
    inputs: [{ name: "vouchee", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "weeklyVouchCount",
    stateMutability: "view",
    inputs: [{ name: "voucher", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "MAX_VOUCHES_PER_WEEK",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
];

export const skinsAbi = [
  {
    type: "function",
    name: "balancesOf",
    stateMutability: "view",
    inputs: [{ name: "wallet", type: "address" }],
    outputs: [{ type: "uint256[]" }],
  },
  {
    type: "function",
    name: "earnedBalancesOf",
    stateMutability: "view",
    inputs: [{ name: "wallet", type: "address" }],
    outputs: [{ type: "uint256[]" }],
  },
];
