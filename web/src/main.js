import QRCode from "qrcode";
import jsQR from "jsqr";
import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  getAddress,
  http,
  isAddress,
  toHex,
  zeroAddress,
} from "viem";
import { skinsAbi, vouchAbi } from "./abi.js";
import {
  CHAIN_ID,
  CHAIN_ID_HEX,
  CHALLENGE_TTL_MS,
  EARNED_SKINS,
  EXPLORER_URL,
  KINDS,
  PAID_SKINS,
  REQUEST_SECONDS,
  ROTATE_MS,
  RPC_URL,
  skinsAddress,
  vouchAddress,
} from "./config.js";
import {
  buildVouchTypedData,
  challengeIsLive,
  decodeDogPayload,
  decodePayload,
  encodeDogPayload,
  encodePayload,
  hashNote,
  rememberChallenges,
} from "./payload.js";
import { ownedEntries, selectWornSkin } from "./worn.js";

const dogeosTestnet = defineChain({
  id: CHAIN_ID,
  name: "DogeOS Chikyū Testnet",
  nativeCurrency: { name: "DOGE", symbol: "DOGE", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: { default: { name: "DogeOS Testnet Explorer", url: EXPLORER_URL } },
});

const publicClient = createPublicClient({ chain: dogeosTestnet, transport: http(RPC_URL) });

const state = {
  account: "",
  provider: null,
  timer: 0,
  dogTimer: 0,
  duckTimer: 0,
  signing: false,
  stopScan: null,
  scanned: null,
  dogCard: null,
  challenges: [],
};

const $ = (id) => document.querySelector(id);

function configured(address) {
  return isAddress(address) && getAddress(address) !== zeroAddress;
}

function setStatus(message, kind = "") {
  const el = $("#status");
  el.textContent = message;
  el.dataset.kind = kind;
}

function describeError(error) {
  if (error && typeof error === "object" && "shortMessage" in error && error.shortMessage) {
    return String(error.shortMessage);
  }
  if (error instanceof Error) return error.message;
  return "Something went wrong.";
}

function showDeployNote() {
  const missing = [];
  if (!configured(vouchAddress)) missing.push("vouchAddress");
  if (!configured(skinsAddress)) missing.push("skinsAddress");
  const note = $("#deploy-note");
  if (missing.length === 0) {
    note.hidden = true;
    return;
  }
  note.hidden = false;
  note.textContent =
    `Contract addresses are still placeholders (${missing.join(", ")}). ` +
    "Transactions stay disabled until Mark deploys and fills web/src/config.js.";
}

function renderAccount() {
  $("#account").textContent = state.account || "Not connected";
}

async function ensureChain(provider) {
  try {
    await provider.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: CHAIN_ID_HEX }],
    });
  } catch (error) {
    if (error && error.code === 4902) {
      await provider.request({
        method: "wallet_addEthereumChain",
        params: [
          {
            chainId: CHAIN_ID_HEX,
            chainName: "DogeOS Chikyū Testnet",
            nativeCurrency: { name: "DOGE", symbol: "DOGE", decimals: 18 },
            rpcUrls: [RPC_URL],
            blockExplorerUrls: [EXPLORER_URL],
          },
        ],
      });
      return;
    }
    throw error;
  }
}

function walletClient() {
  return createWalletClient({
    account: state.account,
    chain: dogeosTestnet,
    transport: custom(state.provider),
  });
}

async function connect() {
  const provider = window.ethereum;
  if (!provider) {
    setStatus("No injected wallet. Install MyDoge or MetaMask, then refresh.", "bad");
    return;
  }
  await ensureChain(provider);
  const accounts = await provider.request({ method: "eth_requestAccounts" });
  if (!accounts || accounts.length === 0) {
    setStatus("The wallet did not return an account.", "bad");
    return;
  }
  state.provider = provider;
  state.account = getAddress(accounts[0]);
  renderAccount();
  $("#connect").textContent = "Connected";
  setStatus(`Connected on DogeOS Chikyū testnet.`);
  if (!$("#dog").hidden) startDogLoop();
  provider.removeListener?.("accountsChanged", onAccountsChanged);
  provider.on?.("accountsChanged", onAccountsChanged);
  refreshWeekly();
}

function onAccountsChanged(accounts) {
  state.account = accounts && accounts[0] ? getAddress(accounts[0]) : "";
  renderAccount();
  refreshWeekly();
}

function randomBytes32() {
  return toHex(crypto.getRandomValues(new Uint8Array(32)));
}

function acceptDogCard(text) {
  let card;
  try {
    card = decodeDogPayload(text.trim());
  } catch (error) {
    state.dogCard = null;
    $("#scanned-dog").textContent = "";
    setStatus(describeError(error), "bad");
    return;
  }
  state.dogCard = card;
  $("#scanned-dog").textContent = `Dog ${card.address}`;
  setStatus("Dog scanned. Start the live QR while you are still together.");
}

async function signOnce() {
  if (!state.account) throw new Error("Connect a wallet first.");
  if (!state.dogCard) throw new Error("Scan the dog's QR first.");
  if (!configured(vouchAddress)) throw new Error("The vouch contract address is not set yet.");
  await ensureChain(state.provider);
  const deadline = BigInt(Math.floor(Date.now() / 1000) + REQUEST_SECONDS);
  const request = {
    voucher: state.dogCard.address,
    vouchee: state.account,
    kind: Number($("#kind").value),
    noteHash: hashNote($("#note").value),
    challenge: state.dogCard.challenge,
    nonce: BigInt(randomBytes32()),
    deadline,
  };
  const typed = buildVouchTypedData({ chainId: CHAIN_ID, verifyingContract: vouchAddress, request });
  const signature = await walletClient().signTypedData(typed);
  const payload = encodePayload({ chainId: CHAIN_ID, verifyingContract: vouchAddress, request, signature });
  const url = await QRCode.toDataURL(payload, { errorCorrectionLevel: "L", margin: 1, width: 280 });
  const img = $("#qr");
  img.src = url;
  img.alt = "Live vouch request QR";
  img.hidden = false;
  startCountdown(deadline);
}

async function rotateDuck() {
  if (state.signing) return;
  state.signing = true;
  try {
    await signOnce();
  } catch (error) {
    stopDuckLoop();
    setStatus(describeError(error), "bad");
  } finally {
    state.signing = false;
  }
}

function startDuckLoop() {
  stopDuckLoop();
  rotateDuck();
  state.duckTimer = window.setInterval(rotateDuck, ROTATE_MS);
}

function stopDuckLoop() {
  window.clearInterval(state.duckTimer);
  state.duckTimer = 0;
}

async function rotateDog() {
  if (!state.account) return;
  const challenge = randomBytes32();
  state.challenges = rememberChallenges(state.challenges, challenge, Date.now(), CHALLENGE_TTL_MS);
  const payload = encodeDogPayload({ address: state.account, challenge });
  const url = await QRCode.toDataURL(payload, { errorCorrectionLevel: "L", margin: 1, width: 280 });
  const img = $("#dog-qr");
  img.src = url;
  img.alt = "Live dog challenge QR";
  img.hidden = false;
  $("#dog-challenge").textContent = "Challenge rotates every 5 seconds.";
}

function startDogLoop() {
  stopDogLoop();
  if (!state.account) return;
  rotateDog().catch((error) => setStatus(describeError(error), "bad"));
  state.dogTimer = window.setInterval(() => {
    rotateDog().catch((error) => setStatus(describeError(error), "bad"));
  }, ROTATE_MS);
}

function stopDogLoop() {
  window.clearInterval(state.dogTimer);
  state.dogTimer = 0;
}

function startCountdown(deadline) {
  window.clearInterval(state.timer);
  const el = $("#countdown");
  const tick = () => {
    const left = Number(deadline) - Math.floor(Date.now() / 1000);
    if (left < 0) {
      el.textContent = "Expired";
      $("#qr").alt = "Expired vouch QR";
      window.clearInterval(state.timer);
      return;
    }
    el.textContent = left === 0 ? "Expires this second" : `${left}s`;
  };
  tick();
  state.timer = window.setInterval(tick, 250);
}

async function refreshWeekly() {
  const el = $("#weekly");
  if (!state.account || !configured(vouchAddress)) {
    el.textContent = "";
    return;
  }
  try {
    const [used, cap] = await Promise.all([
      publicClient.readContract({
        address: vouchAddress,
        abi: vouchAbi,
        functionName: "weeklyVouchCount",
        args: [state.account],
      }),
      publicClient.readContract({
        address: vouchAddress,
        abi: vouchAbi,
        functionName: "MAX_VOUCHES_PER_WEEK",
      }),
    ]);
    el.textContent = `${used} of ${cap} paw stamps used in this epoch week. Revoke does not give a slot back.`;
  } catch (error) {
    el.textContent = describeError(error);
  }
}

function showScanned(text) {
  let decoded;
  try {
    decoded = decodePayload(text.trim());
  } catch (error) {
    state.scanned = null;
    $("#preview").hidden = true;
    setStatus(describeError(error), "bad");
    return;
  }
  if (configured(vouchAddress) && getAddress(decoded.verifyingContract) !== getAddress(vouchAddress)) {
    state.scanned = null;
    $("#preview").hidden = true;
    setStatus("This QR is for a different vouch contract.", "bad");
    return;
  }
  if (!state.account) {
    state.scanned = null;
    $("#preview").hidden = true;
    setStatus("Connect the dog's wallet first.", "bad");
    return;
  }
  if (getAddress(decoded.request.voucher) !== state.account) {
    state.scanned = null;
    $("#preview").hidden = true;
    setStatus("This QR names a different dog.", "bad");
    return;
  }
  if (!challengeIsLive(state.challenges, decoded.request.challenge, Date.now(), CHALLENGE_TTL_MS)) {
    state.scanned = null;
    $("#preview").hidden = true;
    setStatus("That challenge is not one this dog is showing. Ask the duck to scan again.", "bad");
    return;
  }
  state.scanned = decoded;
  const kind = KINDS.find((item) => item.id === decoded.request.kind);
  $("#preview-kind").textContent = kind ? kind.name : `Kind ${decoded.request.kind}`;
  $("#preview-who").textContent = decoded.request.vouchee;
  $("#preview-note").textContent = `Note hash ${decoded.request.noteHash}`;
  const left = Number(decoded.request.deadline) - Math.floor(Date.now() / 1000);
  $("#preview-time").textContent = left < 0 ? "This request is already expired." : `${left}s left on the deadline.`;
  $("#preview").hidden = false;
  setStatus("Duck QR matches this dog. Submit the paw stamp.");
}

async function startScan(video, onText) {
  if (!navigator.mediaDevices?.getUserMedia) {
    setStatus("This browser has no camera API. Paste the payload instead.", "bad");
    return;
  }
  stopScan();
  const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
  video.srcObject = stream;
  video.hidden = false;
  await video.play();
  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  let stopped = false;
  const tick = () => {
    if (stopped) return;
    if (video.readyState >= 2) {
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      ctx.drawImage(video, 0, 0);
      const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const code = jsQR(image.data, image.width, image.height);
      if (code?.data) {
        stopScan();
        onText(code.data);
        return;
      }
    }
    requestAnimationFrame(tick);
  };
  state.stopScan = () => {
    stopped = true;
  };
  requestAnimationFrame(tick);
  setStatus("Looking for a QR code.");
}

function stopScan() {
  state.stopScan?.();
  state.stopScan = null;
  for (const video of [$("#camera"), $("#duck-camera")]) {
    if (!video) continue;
    const stream = video.srcObject;
    if (stream) {
      for (const track of stream.getTracks()) track.stop();
    }
    video.srcObject = null;
    video.hidden = true;
  }
}

async function submitVouch() {
  if (!state.scanned) {
    setStatus("Scan or paste a QR first.", "bad");
    return;
  }
  if (!state.account) {
    setStatus("Connect the dog's wallet first.", "bad");
    return;
  }
  if (!configured(vouchAddress)) {
    setStatus("The vouch contract address is not set yet.", "bad");
    return;
  }
  const left = Number(state.scanned.request.deadline) - Math.floor(Date.now() / 1000);
  if (left < 0) {
    setStatus("That QR has expired. Ask the duck to sign again.", "bad");
    return;
  }
  await ensureChain(state.provider);
  const hash = await walletClient().writeContract({
    address: vouchAddress,
    abi: vouchAbi,
    functionName: "vouch",
    args: [state.scanned.request, state.scanned.signature],
  });
  showTx(hash);
  setStatus("Paw stamp sent.");
  refreshWeekly();
}

async function revoke(event) {
  event.preventDefault();
  if (!state.account) {
    setStatus("Connect the dog's wallet first.", "bad");
    return;
  }
  if (!configured(vouchAddress)) {
    setStatus("The vouch contract address is not set yet.", "bad");
    return;
  }
  const who = $("#revoke-who").value.trim();
  if (!isAddress(who)) {
    setStatus("Enter the vouchee's address.", "bad");
    return;
  }
  await ensureChain(state.provider);
  const hash = await walletClient().writeContract({
    address: vouchAddress,
    abi: vouchAbi,
    functionName: "revoke",
    args: [getAddress(who)],
  });
  showTx(hash);
  setStatus("Vouch revoked. The earned skin stays where it is.");
}

function showTx(hash) {
  const el = $("#tx");
  el.replaceChildren("Transaction ");
  const link = document.createElement("a");
  link.href = `${EXPLORER_URL}/tx/${hash}`;
  link.textContent = hash;
  link.target = "_blank";
  link.rel = "noreferrer";
  el.append(link);
}

function fillTags(element, entries) {
  element.replaceChildren();
  if (entries.length === 0) {
    const empty = document.createElement("span");
    empty.className = "tag muted";
    empty.textContent = "none";
    element.append(empty);
    return;
  }
  for (const entry of entries) {
    const tag = document.createElement("span");
    tag.className = "tag";
    const swatch = document.createElement("i");
    swatch.className = "swatch";
    swatch.style.background = entry.color;
    tag.append(swatch, document.createTextNode(`${entry.name} ×${entry.balance}`));
    element.append(tag);
  }
}

function paintWorn(worn) {
  for (const svg of document.querySelectorAll("#profile .creature")) {
    if (worn) svg.style.setProperty("--coat", worn.color);
    else svg.style.removeProperty("--coat");
  }
  $("#worn-label").textContent = worn ? `${worn.source} · ${worn.name}` : "No skin yet";
}

async function loadProfile() {
  const raw = $("#lookup").value.trim();
  if (!isAddress(raw)) {
    setStatus("Enter an address to look up.", "bad");
    return;
  }
  const who = getAddress(raw);
  let countText = "Vouch contract address is not set.";
  let paid = [];
  let earned = [];
  if (configured(vouchAddress)) {
    const count = await publicClient.readContract({
      address: vouchAddress,
      abi: vouchAbi,
      functionName: "activeVouchCount",
      args: [who],
    });
    countText = `${count} active vouch${count === 1n ? "" : "es"} received`;
  }
  if (configured(skinsAddress)) {
    const [paidBalances, earnedBalances] = await Promise.all([
      publicClient.readContract({
        address: skinsAddress,
        abi: skinsAbi,
        functionName: "balancesOf",
        args: [who],
      }),
      publicClient.readContract({
        address: skinsAddress,
        abi: skinsAbi,
        functionName: "earnedBalancesOf",
        args: [who],
      }),
    ]);
    paid = ownedEntries(paidBalances, PAID_SKINS, "Shop");
    earned = ownedEntries(earnedBalances, EARNED_SKINS, "Earned");
    paintWorn(selectWornSkin(paidBalances, earnedBalances, PAID_SKINS, EARNED_SKINS));
  } else {
    paintWorn(null);
    $("#worn-label").textContent = "Skins contract address is not set";
  }
  $("#vouch-count").textContent = countText;
  fillTags($("#paid-tags"), paid);
  fillTags($("#earned-tags"), earned);
  setStatus(`Loaded ${who}`);
}

function showTab(name) {
  for (const id of ["duck", "dog", "profile"]) {
    $(`#${id}`).hidden = id !== name;
  }
  for (const button of document.querySelectorAll(".tabs button")) {
    button.classList.toggle("active", button.dataset.tab === name);
  }
  stopScan();
  if (name === "dog") startDogLoop();
  else stopDogLoop();
  if (name !== "duck") stopDuckLoop();
}

function bind() {
  $("#connect").addEventListener("click", () => connect().catch((error) => setStatus(describeError(error), "bad")));
  $("#sign").addEventListener("click", () => startDuckLoop());
  $("#stop-sign").addEventListener("click", () => {
    stopDuckLoop();
    setStatus("Live QR stopped.");
  });
  $("#scan-dog").addEventListener("click", () =>
    startScan($("#duck-camera"), acceptDogCard).catch((error) => setStatus(describeError(error), "bad")),
  );
  $("#read-dog").addEventListener("click", () => acceptDogCard($("#dog-paste").value));
  $("#scan").addEventListener("click", () =>
    startScan($("#camera"), showScanned).catch((error) => setStatus(describeError(error), "bad")),
  );
  $("#read-paste").addEventListener("click", () => showScanned($("#paste").value));
  $("#submit").addEventListener("click", () => submitVouch().catch((error) => setStatus(describeError(error), "bad")));
  $("#revoke-form").addEventListener("submit", (event) => {
    revoke(event).catch((error) => setStatus(describeError(error), "bad"));
  });
  $("#load").addEventListener("click", () => loadProfile().catch((error) => setStatus(describeError(error), "bad")));
  for (const button of document.querySelectorAll(".tabs button")) {
    button.addEventListener("click", () => showTab(button.dataset.tab));
  }
  showDeployNote();
}

bind();
