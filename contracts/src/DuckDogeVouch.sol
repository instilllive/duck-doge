// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {DuckDogeSkins} from "./DuckDogeSkins.sol";

/// @title DuckDogeVouch
/// @notice Testnet vouches between two wallets. The duck signs a short-lived
///         request and shows it as a QR code. The dog submits that request
///         from their own wallet.
/// @dev Not a token: there is no transfer function. There is no proxy, no
///      upgrade path, no `delegatecall`, no `selfdestruct`, and no owner.
///      Cosmetic skins are a different contract and are not read here.
///
///      The first successful vouch for a voucher/vouchee pair mints one earned
///      skin to the vouchee. The id cycles by how many first-time vouches that
///      duck has received. Revoke does not burn the skin: it is a normal
///      transferable cosmetic and may already have moved. A later vouch for
///      the same pair does not mint another one.
///
///      The duck's signature names the dog (`voucher`) and includes the dog's
///      live challenge. Only that dog can submit, and only while the deadline
///      is inside a 20 second window. That raises the bar for relaying a
///      screenshot. It still does not prove two humans were in the same place.
contract DuckDogeVouch is EIP712 {
    enum Kind {
        MetInPerson,
        WorkedWith,
        KnowsWell
    }

    /// @notice What the duck signs. `voucher` is the dog. `challenge` is the
    ///         random value from that dog's live QR. `noteHash` may be zero.
    struct VouchRequest {
        address voucher;
        address vouchee;
        Kind kind;
        bytes32 noteHash;
        bytes32 challenge;
        uint256 nonce;
        uint256 deadline;
    }

    /// @notice One dog's vouch for one duck. `active` is cleared by `revoke`.
    struct Vouch {
        address voucher;
        address vouchee;
        Kind kind;
        uint256 timestamp;
        bytes32 noteHash;
        bool active;
    }

    struct WeekCount {
        uint256 epoch;
        uint256 count;
    }

    /// @notice Length of one limit epoch. Epoch `n` is `[n * WEEK, (n + 1) * WEEK)`.
    uint256 public constant WEEK = 7 days;

    /// @notice New vouches one dog may create during a single epoch.
    /// @dev Revoking does not refund a slot. The next epoch starts again at zero.
    ///      This is an epoch bucket, not a rolling 7-day window: three at the
    ///      end of an epoch and three at the start of the next are allowed.
    uint256 public constant MAX_VOUCHES_PER_WEEK = 3;

    /// @notice Latest `deadline` the contract will accept, measured from `block.timestamp`.
    /// @dev The page signs for 15 seconds and refreshes about every 5. The
    ///      extra 5 seconds is inclusion slack.
    uint256 public constant MAX_DEADLINE_WINDOW = 20 seconds;

    bytes32 private constant VOUCH_REQUEST_TYPEHASH = keccak256(
        "VouchRequest(address voucher,address vouchee,uint8 kind,bytes32 noteHash,bytes32 challenge,uint256 nonce,uint256 deadline)"
    );

    event Vouched(
        address indexed voucher, address indexed vouchee, Kind kind, bytes32 noteHash, uint256 nonce, uint256 timestamp
    );

    event VouchRevoked(address indexed voucher, address indexed vouchee);
    event EarnedSkinMinted(address indexed voucher, address indexed vouchee, uint256 earnedIndex);

    error Expired(uint256 deadline, uint256 currentTime);
    error DeadlineTooFar(uint256 deadline, uint256 maxDeadline);
    error BadSignature();
    error WrongVoucher();
    error SelfVouch();
    error NonceUsed(uint256 nonce);
    error DuplicateVouch();
    error WeeklyLimit(uint256 epoch, uint256 count);
    error VouchNotActive();
    error ZeroSkins();
    error NoEarnedSkins();

    /// @notice Skins contract that receives earned mints. Fixed at deploy.
    DuckDogeSkins public immutable skins;

    mapping(address voucher => mapping(address vouchee => Vouch vouch)) private _vouches;
    mapping(address vouchee => uint256 count) private _activeVouchCount;
    mapping(address vouchee => uint256 count) private _lifetimeReceived;
    mapping(address voucher => mapping(address vouchee => bool minted)) private _earnedMinted;
    mapping(address vouchee => mapping(uint256 nonce => bool used)) private _usedNonce;
    mapping(address voucher => WeekCount weekCount) private _weekCount;

    constructor(DuckDogeSkins skins_) EIP712("DuckDogeVouch", "1") {
        if (address(skins_) == address(0)) revert ZeroSkins();
        if (skins_.earnedSkinCount() == 0) revert NoEarnedSkins();
        skins = skins_;
    }

    /// @notice Dog submits a request the duck already signed.
    /// @dev `voucheeSignature` must recover to `request.vouchee` over the
    ///      EIP-712 digest of `request` for this contract and chain.
    function vouch(VouchRequest calldata request, bytes calldata voucheeSignature) external {
        uint256 currentTime = block.timestamp;
        if (currentTime > request.deadline) revert Expired(request.deadline, currentTime);
        uint256 maxDeadline = currentTime + MAX_DEADLINE_WINDOW;
        if (request.deadline > maxDeadline) revert DeadlineTooFar(request.deadline, maxDeadline);

        address signer = ECDSA.recoverCalldata(_hashTypedDataV4(_hashRequest(request)), voucheeSignature);
        if (signer != request.vouchee) revert BadSignature();
        if (msg.sender != request.voucher) revert WrongVoucher();
        if (msg.sender == request.vouchee) revert SelfVouch();

        if (_usedNonce[request.vouchee][request.nonce]) revert NonceUsed(request.nonce);
        _usedNonce[request.vouchee][request.nonce] = true;

        if (_vouches[msg.sender][request.vouchee].active) revert DuplicateVouch();

        enforceWeeklyLimit(msg.sender);

        _vouches[msg.sender][request.vouchee] = Vouch({
            voucher: msg.sender,
            vouchee: request.vouchee,
            kind: request.kind,
            timestamp: currentTime,
            noteHash: request.noteHash,
            active: true
        });
        _activeVouchCount[request.vouchee] += 1;

        emit Vouched(msg.sender, request.vouchee, request.kind, request.noteHash, request.nonce, currentTime);

        // State is written before the skins call. A receiver hook cannot mint
        // a second earned skin for this same pair. Revoke does not clear this flag.
        if (!_earnedMinted[msg.sender][request.vouchee]) {
            _earnedMinted[msg.sender][request.vouchee] = true;
            uint256 earnedIndex = _lifetimeReceived[request.vouchee] % skins.earnedSkinCount();
            _lifetimeReceived[request.vouchee] += 1;
            skins.mintEarned(request.vouchee, earnedIndex);
            emit EarnedSkinMinted(msg.sender, request.vouchee, earnedIndex);
        }
    }

    /// @notice Dog withdraws the active vouch they gave `vouchee`.
    /// @dev Does not burn the earned skin. The record stays in `getVouch` with
    ///      `active` false. A third party, including the duck, has no vouch
    ///      under their own address, so the call reverts with `VouchNotActive`.
    function revoke(address vouchee) external {
        Vouch storage existing = _vouches[msg.sender][vouchee];
        if (!existing.active) revert VouchNotActive();
        existing.active = false;
        _activeVouchCount[vouchee] -= 1;
        emit VouchRevoked(msg.sender, vouchee);
    }

    /// @notice Active vouches this address has received.
    function activeVouchCount(address vouchee) external view returns (uint256) {
        return _activeVouchCount[vouchee];
    }

    /// @notice Vouch from `voucher` to `vouchee`, including a revoked one.
    /// @dev An unknown pair returns the zero struct (`active` is false).
    function getVouch(address voucher, address vouchee) external view returns (Vouch memory) {
        return _vouches[voucher][vouchee];
    }

    /// @notice Vouches `voucher` has created in the current epoch week.
    /// @dev An epoch that does not match the stored one reports zero.
    function weeklyVouchCount(address voucher) external view returns (uint256) {
        WeekCount storage usage = _weekCount[voucher];
        uint256 epoch = block.timestamp / WEEK;
        if (usage.epoch != epoch) return 0;
        return usage.count;
    }

    /// @notice EIP-712 digest the duck signs for `request`.
    function hashVouchRequest(VouchRequest calldata request) external view returns (bytes32) {
        return _hashTypedDataV4(_hashRequest(request));
    }

    /// @dev Consumes one slot in `block.timestamp / WEEK`. The fourth vouch in
    ///      that epoch reverts. A later epoch stores a fresh count of one.
    function enforceWeeklyLimit(address voucher) internal {
        uint256 epoch = block.timestamp / WEEK;
        WeekCount storage usage = _weekCount[voucher];
        uint256 count;
        if (usage.epoch == epoch) {
            count = usage.count;
        } else {
            count = 0;
        }
        if (count >= MAX_VOUCHES_PER_WEEK) revert WeeklyLimit(epoch, count);
        usage.epoch = epoch;
        usage.count = count + 1;
    }

    function _hashRequest(VouchRequest calldata request) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                VOUCH_REQUEST_TYPEHASH,
                request.voucher,
                request.vouchee,
                request.kind,
                request.noteHash,
                request.challenge,
                request.nonce,
                request.deadline
            )
        );
    }
}
