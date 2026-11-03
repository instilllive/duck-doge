// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {DuckDogeSkins} from "../src/DuckDogeSkins.sol";
import {DuckDogeVouch} from "../src/DuckDogeVouch.sol";

contract DuckDogeVouchTest is Test {
    uint256 internal constant WEEK = 7 days;
    uint256 internal constant START = 1_700_000_000;

    bytes32 internal constant REQUEST_TYPEHASH =
        keccak256("VouchRequest(address vouchee,uint8 kind,bytes32 noteHash,uint256 nonce,uint256 deadline)");
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    event Vouched(
        address indexed voucher,
        address indexed vouchee,
        DuckDogeVouch.Kind kind,
        bytes32 noteHash,
        uint256 nonce,
        uint256 timestamp
    );
    event VouchRevoked(address indexed voucher, address indexed vouchee);

    uint256 internal constant PAID = 4;
    uint256 internal constant EARNED = 2;

    DuckDogeSkins internal skins;
    DuckDogeVouch internal vouch;
    address internal dog;
    uint256 internal dogKey;
    address internal duck;
    uint256 internal duckKey;
    address internal other;
    uint256 internal otherKey;

    function setUp() public {
        vm.warp(START);
        skins = new DuckDogeSkins(0.01 ether, PAID, EARNED, "", address(this));
        vouch = new DuckDogeVouch(skins);
        skins.setMinter(address(vouch));
        (dog, dogKey) = makeAddrAndKey("dog");
        (duck, duckKey) = makeAddrAndKey("duck");
        (other, otherKey) = makeAddrAndKey("other");

        assertEq(vouch.WEEK(), WEEK);
        assertEq(vouch.MAX_VOUCHES_PER_WEEK(), 3);
        assertEq(vouch.MAX_DEADLINE_WINDOW(), 90 seconds);
        assertEq(vouch.activeVouchCount(duck), 0);
        assertEq(vouch.weeklyVouchCount(dog), 0);
        assertEq(block.timestamp / WEEK, START / WEEK);
        assertTrue(START / WEEK != 0);
    }

    function test_vouch_valid_storesFieldsEmitsAndCounts() public {
        bytes32 note = keccak256("met by the river");
        DuckDogeVouch.VouchRequest memory request =
            _request(duck, DuckDogeVouch.Kind.MetInPerson, note, 11, block.timestamp + 60);
        bytes memory signature = _sign(vouch, duckKey, request);

        assertEq(ECDSA.recover(vouch.hashVouchRequest(request), signature), duck);

        vm.prank(dog);
        vm.expectEmit(true, true, true, true, address(vouch));
        emit Vouched(dog, duck, DuckDogeVouch.Kind.MetInPerson, note, 11, block.timestamp);
        vouch.vouch(request, signature);

        DuckDogeVouch.Vouch memory stored = vouch.getVouch(dog, duck);
        assertEq(stored.voucher, dog);
        assertEq(stored.vouchee, duck);
        assertEq(uint8(stored.kind), uint8(DuckDogeVouch.Kind.MetInPerson));
        assertEq(stored.timestamp, block.timestamp);
        assertEq(stored.noteHash, note);
        assertTrue(stored.active);
        assertEq(vouch.activeVouchCount(duck), 1);
        assertEq(vouch.activeVouchCount(dog), 0);
        assertEq(vouch.weeklyVouchCount(dog), 1);
        assertEq(skins.balanceOf(duck, PAID), 1);
        assertEq(skins.earnedBalancesOf(duck)[0], 1);
        assertEq(skins.earnedBalancesOf(duck)[1], 0);

        DuckDogeVouch.Vouch memory reverse = vouch.getVouch(duck, dog);
        assertEq(reverse.voucher, address(0));
        assertFalse(reverse.active);
    }

    function test_vouch_acceptsZeroNoteHash() public {
        DuckDogeVouch.Vouch memory stored =
            _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.KnowsWell, bytes32(0), 0, block.timestamp + 60));
        assertEq(stored.noteHash, bytes32(0));
        assertEq(uint8(stored.kind), uint8(DuckDogeVouch.Kind.KnowsWell));
        assertTrue(stored.active);
    }

    function test_vouch_storesEachKind() public {
        DuckDogeVouch.Kind[3] memory kinds =
            [DuckDogeVouch.Kind.MetInPerson, DuckDogeVouch.Kind.WorkedWith, DuckDogeVouch.Kind.KnowsWell];
        for (uint256 i = 0; i < kinds.length; ++i) {
            (address person, uint256 key) = makeAddrAndKey(string.concat("kind-", vm.toString(i)));
            DuckDogeVouch.Vouch memory stored =
                _give(dog, key, _request(person, kinds[i], bytes32(uint256(i + 1)), i + 1, block.timestamp + 60));
            assertEq(uint8(stored.kind), uint8(kinds[i]));
        }
    }

    function test_vouch_acceptsDeadlineAtNowAndAtWindowEnd() public {
        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 1, block.timestamp));

        (address second, uint256 secondKey) = makeAddrAndKey("window-end");
        _give(
            dog,
            secondKey,
            _request(second, DuckDogeVouch.Kind.WorkedWith, bytes32(uint256(2)), 2, block.timestamp + 90 seconds)
        );
        assertEq(vouch.activeVouchCount(duck), 1);
        assertEq(vouch.activeVouchCount(second), 1);
    }

    function test_vouch_revertsWhenDeadlineExpired() public {
        DuckDogeVouch.VouchRequest memory request =
            _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 4, block.timestamp + 60);
        bytes memory signature = _sign(vouch, duckKey, request);

        vm.warp(request.deadline + 1);
        vm.prank(dog);
        vm.expectRevert(abi.encodeWithSelector(DuckDogeVouch.Expired.selector, request.deadline, block.timestamp));
        vouch.vouch(request, signature);

        assertEq(vouch.activeVouchCount(duck), 0);
        assertEq(vouch.weeklyVouchCount(dog), 0);
        assertFalse(vouch.getVouch(dog, duck).active);

        vm.warp(START);
        DuckDogeVouch.VouchRequest memory past =
            _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 4, block.timestamp - 1);
        bytes memory pastSignature = _sign(vouch, duckKey, past);
        vm.prank(dog);
        vm.expectRevert(abi.encodeWithSelector(DuckDogeVouch.Expired.selector, past.deadline, block.timestamp));
        vouch.vouch(past, pastSignature);

        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 4, block.timestamp + 60));
        assertEq(vouch.activeVouchCount(duck), 1);
    }

    function test_vouch_revertsWhenDeadlineTooFar() public {
        uint256 deadline = block.timestamp + 91 seconds;
        DuckDogeVouch.VouchRequest memory request =
            _request(duck, DuckDogeVouch.Kind.WorkedWith, keccak256("later"), 5, deadline);
        bytes memory signature = _sign(vouch, duckKey, request);
        vm.prank(dog);
        vm.expectRevert(
            abi.encodeWithSelector(DuckDogeVouch.DeadlineTooFar.selector, deadline, block.timestamp + 90 seconds)
        );
        vouch.vouch(request, signature);

        assertEq(vouch.activeVouchCount(duck), 0);
        assertEq(vouch.weeklyVouchCount(dog), 0);

        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.WorkedWith, keccak256("later"), 5, block.timestamp + 60));
        assertTrue(vouch.getVouch(dog, duck).active);
    }

    function test_vouch_revertsWhenDeadlineMathOverflows() public {
        vm.warp(type(uint256).max - 89);
        DuckDogeVouch.VouchRequest memory request =
            _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 1, type(uint256).max);
        bytes memory signature = _sign(vouch, duckKey, request);

        vm.prank(dog);
        vm.expectRevert(stdError.arithmeticError);
        vouch.vouch(request, signature);
        assertEq(vouch.activeVouchCount(duck), 0);
    }

    function test_vouch_revertsOnForgedSignature() public {
        DuckDogeVouch.VouchRequest memory request =
            _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 6, block.timestamp + 60);
        bytes memory forged = _sign(vouch, otherKey, request);

        vm.prank(dog);
        vm.expectRevert(DuckDogeVouch.BadSignature.selector);
        vouch.vouch(request, forged);
        assertEq(vouch.activeVouchCount(duck), 0);
    }

    function test_vouch_revertsOnTamperedRequest() public {
        DuckDogeVouch.VouchRequest memory request =
            _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 7, block.timestamp + 60);
        bytes memory signature = _sign(vouch, duckKey, request);
        request.kind = DuckDogeVouch.Kind.KnowsWell;

        vm.prank(dog);
        vm.expectRevert(DuckDogeVouch.BadSignature.selector);
        vouch.vouch(request, signature);
    }

    function test_vouch_revertsOnMalformedSignature() public {
        DuckDogeVouch.VouchRequest memory request =
            _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 8, block.timestamp + 60);

        vm.prank(dog);
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, 2));
        vouch.vouch(request, hex"abcd");
        assertEq(vouch.activeVouchCount(duck), 0);
    }

    function test_vouch_revertsOnSignatureForOtherDeploymentOrChain() public {
        DuckDogeVouch.VouchRequest memory request =
            _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 9, block.timestamp + 60);
        bytes memory signature = _sign(vouch, duckKey, request);

        DuckDogeVouch otherDeployment = new DuckDogeVouch(skins);
        vm.prank(dog);
        vm.expectRevert(DuckDogeVouch.BadSignature.selector);
        otherDeployment.vouch(request, signature);

        vm.chainId(block.chainid + 1);
        vm.prank(dog);
        vm.expectRevert(DuckDogeVouch.BadSignature.selector);
        vouch.vouch(request, signature);
        assertEq(vouch.activeVouchCount(duck), 0);
    }

    function test_vouch_revertsOnReusedNonce() public {
        DuckDogeVouch.VouchRequest memory request =
            _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 12, block.timestamp + 60);
        bytes memory signature = _sign(vouch, duckKey, request);
        vm.prank(dog);
        vouch.vouch(request, signature);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(DuckDogeVouch.NonceUsed.selector, 12));
        vouch.vouch(request, signature);
        assertEq(vouch.activeVouchCount(duck), 1);

        DuckDogeVouch.VouchRequest memory again =
            _request(duck, DuckDogeVouch.Kind.WorkedWith, keccak256("again"), 12, block.timestamp + 30);
        bytes memory againSignature = _sign(vouch, duckKey, again);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(DuckDogeVouch.NonceUsed.selector, 12));
        vouch.vouch(again, againSignature);
        assertEq(vouch.getVouch(other, duck).voucher, address(0));
    }

    function test_vouch_allowsSameNonceForADifferentVouchee() public {
        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 15, block.timestamp + 60));
        DuckDogeVouch.Vouch memory stored =
            _give(dog, otherKey, _request(other, DuckDogeVouch.Kind.WorkedWith, bytes32(0), 15, block.timestamp + 60));
        assertTrue(stored.active);
        assertEq(vouch.activeVouchCount(duck), 1);
        assertEq(vouch.activeVouchCount(other), 1);
    }

    function test_vouch_revertsOnSelfVouch() public {
        DuckDogeVouch.VouchRequest memory request =
            _request(duck, DuckDogeVouch.Kind.KnowsWell, keccak256("self"), 16, block.timestamp + 60);
        bytes memory signature = _sign(vouch, duckKey, request);

        vm.prank(duck);
        vm.expectRevert(DuckDogeVouch.SelfVouch.selector);
        vouch.vouch(request, signature);

        assertEq(vouch.activeVouchCount(duck), 0);
        assertEq(vouch.weeklyVouchCount(duck), 0);
        assertFalse(vouch.getVouch(duck, duck).active);

        _give(dog, duckKey, request);
        assertEq(vouch.activeVouchCount(duck), 1);
        assertEq(vouch.getVouch(dog, duck).voucher, dog);
    }

    function test_vouch_revertsOnDuplicate() public {
        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 21, block.timestamp + 60));

        DuckDogeVouch.VouchRequest memory again =
            _request(duck, DuckDogeVouch.Kind.KnowsWell, keccak256("second"), 22, block.timestamp + 45);
        bytes memory againSignature = _sign(vouch, duckKey, again);
        vm.prank(dog);
        vm.expectRevert(DuckDogeVouch.DuplicateVouch.selector);
        vouch.vouch(again, againSignature);

        assertEq(vouch.weeklyVouchCount(dog), 1);
        assertEq(vouch.activeVouchCount(duck), 1);
        assertEq(uint8(vouch.getVouch(dog, duck).kind), uint8(DuckDogeVouch.Kind.MetInPerson));

        _give(
            other, duckKey, _request(duck, DuckDogeVouch.Kind.WorkedWith, bytes32(uint256(3)), 23, block.timestamp + 60)
        );
        assertEq(vouch.activeVouchCount(duck), 2);
    }

    function test_vouch_weeklyLimitHitsAndResetsNextEpoch() public {
        assertEq(vouch.weeklyVouchCount(dog), 0);

        address[3] memory people = [duck, other, makeAddr("third")];
        uint256[3] memory keys = [duckKey, otherKey, 0];
        (people[2], keys[2]) = makeAddrAndKey("third");

        for (uint256 i = 0; i < 3; ++i) {
            _give(
                dog,
                keys[i],
                _request(
                    people[i], DuckDogeVouch.Kind.MetInPerson, bytes32(uint256(i + 1)), 30 + i, block.timestamp + 60
                )
            );
            assertEq(vouch.weeklyVouchCount(dog), i + 1);
        }

        (address fourth, uint256 fourthKey) = makeAddrAndKey("fourth");
        DuckDogeVouch.VouchRequest memory over =
            _request(fourth, DuckDogeVouch.Kind.WorkedWith, bytes32(0), 40, block.timestamp + 60);
        bytes memory overSignature = _sign(vouch, fourthKey, over);
        uint256 epoch = block.timestamp / WEEK;
        vm.prank(dog);
        vm.expectRevert(abi.encodeWithSelector(DuckDogeVouch.WeeklyLimit.selector, epoch, 3));
        vouch.vouch(over, overSignature);
        assertEq(vouch.weeklyVouchCount(dog), 3);
        assertEq(vouch.activeVouchCount(fourth), 0);
        assertEq(skins.balanceOf(fourth, PAID), 0);

        vm.warp((epoch + 1) * WEEK - 1);
        DuckDogeVouch.VouchRequest memory stillOver =
            _request(fourth, DuckDogeVouch.Kind.WorkedWith, bytes32(0), 40, block.timestamp + 60);
        bytes memory stillOverSignature = _sign(vouch, fourthKey, stillOver);
        vm.prank(dog);
        vm.expectRevert(abi.encodeWithSelector(DuckDogeVouch.WeeklyLimit.selector, epoch, 3));
        vouch.vouch(stillOver, stillOverSignature);
        assertEq(vouch.weeklyVouchCount(dog), 3);

        vm.warp((epoch + 1) * WEEK);
        assertEq(vouch.weeklyVouchCount(dog), 0);
        _give(dog, fourthKey, _request(fourth, DuckDogeVouch.Kind.WorkedWith, bytes32(0), 41, block.timestamp + 60));
        assertEq(vouch.weeklyVouchCount(dog), 1);
        assertEq(vouch.activeVouchCount(fourth), 1);
        assertEq(vouch.activeVouchCount(duck), 1);
    }

    function test_vouch_weekZeroStillCapsAtThree() public {
        vm.warp(5_000);
        assertEq(block.timestamp / WEEK, 0);
        assertEq(vouch.weeklyVouchCount(dog), 0);

        for (uint256 i = 0; i < 3; ++i) {
            (address person, uint256 key) = makeAddrAndKey(string.concat("week0-", vm.toString(i)));
            _give(dog, key, _request(person, DuckDogeVouch.Kind.MetInPerson, bytes32(0), i, block.timestamp + 60));
        }
        assertEq(vouch.weeklyVouchCount(dog), 3);

        (address extra, uint256 extraKey) = makeAddrAndKey("week0-extra");
        DuckDogeVouch.VouchRequest memory over =
            _request(extra, DuckDogeVouch.Kind.KnowsWell, bytes32(0), 99, block.timestamp + 60);
        bytes memory overSignature = _sign(vouch, extraKey, over);
        vm.prank(dog);
        vm.expectRevert(abi.encodeWithSelector(DuckDogeVouch.WeeklyLimit.selector, 0, 3));
        vouch.vouch(over, overSignature);
        assertEq(vouch.activeVouchCount(extra), 0);
    }

    function test_vouch_revokeDoesNotRefundWeeklySlot() public {
        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 1, block.timestamp + 60));
        _give(dog, otherKey, _request(other, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 1, block.timestamp + 60));
        (address third, uint256 thirdKey) = makeAddrAndKey("refund-third");
        _give(dog, thirdKey, _request(third, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 1, block.timestamp + 60));

        vm.prank(dog);
        vouch.revoke(duck);
        vm.prank(dog);
        vouch.revoke(other);
        vm.prank(dog);
        vouch.revoke(third);
        assertEq(vouch.weeklyVouchCount(dog), 3);
        assertEq(vouch.activeVouchCount(duck), 0);

        (address fourth, uint256 fourthKey) = makeAddrAndKey("refund-fourth");
        DuckDogeVouch.VouchRequest memory over =
            _request(fourth, DuckDogeVouch.Kind.WorkedWith, bytes32(0), 2, block.timestamp + 60);
        bytes memory overSignature = _sign(vouch, fourthKey, over);
        vm.prank(dog);
        vm.expectRevert(abi.encodeWithSelector(DuckDogeVouch.WeeklyLimit.selector, block.timestamp / WEEK, 3));
        vouch.vouch(over, overSignature);
    }

    function test_vouch_weeklyLimitIsPerVoucher() public {
        for (uint256 i = 0; i < 3; ++i) {
            (address person, uint256 key) = makeAddrAndKey(string.concat("cap-", vm.toString(i)));
            _give(dog, key, _request(person, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 1, block.timestamp + 60));
        }
        _give(other, duckKey, _request(duck, DuckDogeVouch.Kind.KnowsWell, bytes32(0), 7, block.timestamp + 60));
        assertEq(vouch.weeklyVouchCount(dog), 3);
        assertEq(vouch.weeklyVouchCount(other), 1);
        assertTrue(vouch.getVouch(other, duck).active);
    }

    function test_revoke_byVoucherClearsActiveAndEmits() public {
        bytes32 note = keccak256("park");
        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.WorkedWith, note, 50, block.timestamp + 60));
        assertEq(vouch.activeVouchCount(duck), 1);

        vm.prank(dog);
        vm.expectEmit(true, true, true, true, address(vouch));
        emit VouchRevoked(dog, duck);
        vouch.revoke(duck);

        DuckDogeVouch.Vouch memory stored = vouch.getVouch(dog, duck);
        assertFalse(stored.active);
        assertEq(stored.voucher, dog);
        assertEq(stored.vouchee, duck);
        assertEq(stored.noteHash, note);
        assertEq(uint8(stored.kind), uint8(DuckDogeVouch.Kind.WorkedWith));
        assertEq(vouch.activeVouchCount(duck), 0);
    }

    function test_revoke_revertsWhenNoneExists() public {
        vm.prank(dog);
        vm.expectRevert(DuckDogeVouch.VouchNotActive.selector);
        vouch.revoke(duck);
        assertEq(vouch.activeVouchCount(duck), 0);
        assertEq(vouch.getVouch(dog, duck).timestamp, 0);
    }

    function test_revoke_revertsForNonVoucher() public {
        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 60, block.timestamp + 60));

        vm.prank(duck);
        vm.expectRevert(DuckDogeVouch.VouchNotActive.selector);
        vouch.revoke(duck);

        vm.prank(other);
        vm.expectRevert(DuckDogeVouch.VouchNotActive.selector);
        vouch.revoke(duck);

        assertTrue(vouch.getVouch(dog, duck).active);
        assertEq(vouch.activeVouchCount(duck), 1);
    }

    function test_revoke_secondTimeReverts() public {
        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 61, block.timestamp + 60));
        vm.prank(dog);
        vouch.revoke(duck);

        vm.prank(dog);
        vm.expectRevert(DuckDogeVouch.VouchNotActive.selector);
        vouch.revoke(duck);
        assertEq(vouch.activeVouchCount(duck), 0);
    }

    function test_count_changesWithVouchAndRevoke() public {
        assertEq(vouch.activeVouchCount(duck), 0);

        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 70, block.timestamp + 60));
        assertEq(vouch.activeVouchCount(duck), 1);

        _give(
            other, duckKey, _request(duck, DuckDogeVouch.Kind.KnowsWell, bytes32(uint256(4)), 71, block.timestamp + 60)
        );
        assertEq(vouch.activeVouchCount(duck), 2);
        assertEq(vouch.activeVouchCount(dog), 0);

        vm.prank(dog);
        vouch.revoke(duck);
        assertEq(vouch.activeVouchCount(duck), 1);
        assertTrue(vouch.getVouch(other, duck).active);
        assertFalse(vouch.getVouch(dog, duck).active);

        vm.prank(other);
        vouch.revoke(duck);
        assertEq(vouch.activeVouchCount(duck), 0);
    }

    function test_reVouch_afterRevokeUsesANewNonce() public {
        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 80, block.timestamp + 60));
        vm.prank(dog);
        vouch.revoke(duck);

        DuckDogeVouch.Vouch memory stored = _give(
            dog, duckKey, _request(duck, DuckDogeVouch.Kind.KnowsWell, keccak256("again"), 81, block.timestamp + 60)
        );
        assertTrue(stored.active);
        assertEq(uint8(stored.kind), uint8(DuckDogeVouch.Kind.KnowsWell));
        assertEq(vouch.activeVouchCount(duck), 1);
        assertEq(vouch.weeklyVouchCount(dog), 2);
        assertEq(skins.balanceOf(duck, PAID), 1);
        assertEq(skins.earnedBalancesOf(duck)[0], 1);
        assertEq(skins.earnedBalancesOf(duck)[1], 0);
    }

    function test_vouch_mintsOneEarnedSkinPerPairAndCycles() public {
        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 1, block.timestamp + 60));
        assertEq(skins.earnedBalancesOf(duck)[0], 1);

        _give(other, duckKey, _request(duck, DuckDogeVouch.Kind.WorkedWith, bytes32(0), 2, block.timestamp + 60));
        assertEq(skins.earnedBalancesOf(duck)[1], 1);

        (address third,) = makeAddrAndKey("third-voucher");
        _give(third, duckKey, _request(duck, DuckDogeVouch.Kind.KnowsWell, bytes32(0), 3, block.timestamp + 60));
        uint256[] memory earned = skins.earnedBalancesOf(duck);
        assertEq(earned[0], 2);
        assertEq(earned[1], 1);
        assertEq(skins.balanceOf(duck, PAID), 2);
        assertEq(skins.balanceOf(duck, PAID + 1), 1);

        _give(dog, otherKey, _request(other, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 1, block.timestamp + 60));
        assertEq(skins.earnedBalancesOf(other)[0], 1);
        assertEq(skins.earnedBalancesOf(other)[1], 0);
        assertEq(earned[0], 2);
    }

    function test_revoke_doesNotBurnEarnedSkin() public {
        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 8, block.timestamp + 60));
        vm.prank(duck);
        skins.safeTransferFrom(duck, other, PAID, 1, "");

        vm.prank(dog);
        vouch.revoke(duck);

        assertFalse(vouch.getVouch(dog, duck).active);
        assertEq(vouch.activeVouchCount(duck), 0);
        assertEq(skins.balanceOf(duck, PAID), 0);
        assertEq(skins.balanceOf(other, PAID), 1);

        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.KnowsWell, bytes32(0), 9, block.timestamp + 60));
        assertTrue(vouch.getVouch(dog, duck).active);
        assertEq(skins.balanceOf(duck, PAID), 0);
        assertEq(skins.balanceOf(other, PAID), 1);
        assertEq(skins.earnedBalancesOf(duck)[0], 0);
        assertEq(skins.earnedBalancesOf(other)[0], 1);
    }

    function test_constructor_revertsOnZeroSkins() public {
        vm.expectRevert(DuckDogeVouch.ZeroSkins.selector);
        new DuckDogeVouch(DuckDogeSkins(address(0)));
    }

    function test_constructor_revertsWhenNoEarnedSkins() public {
        DuckDogeSkins paidOnly = new DuckDogeSkins(0.01 ether, PAID, 0, "", address(this));
        vm.expectRevert(DuckDogeVouch.NoEarnedSkins.selector);
        new DuckDogeVouch(paidOnly);
    }

    function test_vouch_revertsWhenMinterIsUnset() public {
        DuckDogeSkins fresh = new DuckDogeSkins(0.01 ether, PAID, EARNED, "", address(this));
        DuckDogeVouch unwired = new DuckDogeVouch(fresh);
        DuckDogeVouch.VouchRequest memory request =
            _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 5, block.timestamp + 60);
        bytes memory signature = _sign(unwired, duckKey, request);

        vm.prank(dog);
        vm.expectRevert(abi.encodeWithSelector(DuckDogeSkins.NotMinter.selector, address(unwired)));
        unwired.vouch(request, signature);

        assertEq(unwired.activeVouchCount(duck), 0);
        assertFalse(unwired.getVouch(dog, duck).active);
        assertEq(fresh.balanceOf(duck, PAID), 0);
    }

    function test_getVouch_unknownPairIsEmpty() public view {
        DuckDogeVouch.Vouch memory stored = vouch.getVouch(dog, duck);
        assertEq(stored.voucher, address(0));
        assertEq(stored.vouchee, address(0));
        assertEq(stored.timestamp, 0);
        assertEq(stored.noteHash, bytes32(0));
        assertFalse(stored.active);
        assertEq(vouch.activeVouchCount(address(0)), 0);
    }

    function test_hash_matchesManualEip712() public view {
        assertEq(REQUEST_TYPEHASH, hex"bec20a566ea3c380327c688353c94b513d0b7cce85c58342c2a61de5a9ceee06");
        assertEq(DOMAIN_TYPEHASH, hex"8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f");

        DuckDogeVouch.VouchRequest memory request =
            _request(duck, DuckDogeVouch.Kind.WorkedWith, keccak256("note"), 90, 1_700_000_060);
        bytes32 structHash = keccak256(
            abi.encode(
                REQUEST_TYPEHASH, request.vouchee, request.kind, request.noteHash, request.nonce, request.deadline
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256(bytes("DuckDogeVouch")), keccak256(bytes("1")), block.chainid, address(vouch)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        assertEq(digest, vouch.hashVouchRequest(request));

        (bytes1 fields, string memory name, string memory version, uint256 chainId, address verifying,,) =
            vouch.eip712Domain();
        assertEq(fields, hex"0f");
        assertEq(name, "DuckDogeVouch");
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifying, address(vouch));
    }

    function test_paidSkinsDoNotGateVouches() public {
        vm.deal(duck, 1 ether);
        vm.prank(duck);
        skins.mint{value: 0.02 ether}(1, 2);

        _give(dog, duckKey, _request(duck, DuckDogeVouch.Kind.MetInPerson, bytes32(0), 100, block.timestamp + 60));

        assertEq(skins.balanceOf(duck, 1), 2);
        assertEq(skins.balanceOf(dog, 1), 0);
        assertEq(skins.balancesOf(duck)[1], 2);
        assertEq(skins.balanceOf(duck, PAID), 1);
        assertEq(vouch.activeVouchCount(duck), 1);
        assertTrue(vouch.getVouch(dog, duck).active);

        (address bare, uint256 bareKey) = makeAddrAndKey("bare");
        _give(dog, bareKey, _request(bare, DuckDogeVouch.Kind.WorkedWith, bytes32(0), 1, block.timestamp + 60));
        assertEq(skins.balancesOf(bare)[0], 0);
        assertEq(skins.earnedBalancesOf(bare)[0], 1);
        assertEq(vouch.activeVouchCount(bare), 1);
    }

    function _request(address vouchee, DuckDogeVouch.Kind kind, bytes32 noteHash, uint256 nonce, uint256 deadline)
        internal
        pure
        returns (DuckDogeVouch.VouchRequest memory)
    {
        return DuckDogeVouch.VouchRequest({
            vouchee: vouchee, kind: kind, noteHash: noteHash, nonce: nonce, deadline: deadline
        });
    }

    function _sign(DuckDogeVouch target, uint256 key, DuckDogeVouch.VouchRequest memory request)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, target.hashVouchRequest(request));
        return abi.encodePacked(r, s, v);
    }

    function _give(address voucher, uint256 voucheeKey, DuckDogeVouch.VouchRequest memory request)
        internal
        returns (DuckDogeVouch.Vouch memory stored)
    {
        bytes memory signature = _sign(vouch, voucheeKey, request);
        vm.prank(voucher);
        vouch.vouch(request, signature);
        stored = vouch.getVouch(voucher, request.vouchee);
        assertEq(stored.voucher, voucher);
        assertEq(stored.vouchee, request.vouchee);
        assertEq(uint8(stored.kind), uint8(request.kind));
        assertEq(stored.timestamp, block.timestamp);
        assertEq(stored.noteHash, request.noteHash);
        assertTrue(stored.active);
    }
}
