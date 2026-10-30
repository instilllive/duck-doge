// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {DuckDogeSkins} from "../src/DuckDogeSkins.sol";

contract RejectingOwner {
    receive() external payable {
        revert("reject");
    }

    function withdrawSkins(DuckDogeSkins skins) external {
        skins.withdraw();
    }
}

contract DuckDogeSkinsTest is Test {
    uint256 internal constant PRICE = 0.01 ether;
    uint256 internal constant SKIN_COUNT = 4;

    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event Paused(address account);
    event Unpaused(address account);
    event Withdrawn(address indexed to, uint256 amount);

    DuckDogeSkins internal skins;
    address internal owner = makeAddr("owner");
    address internal player = makeAddr("player");

    function setUp() public {
        skins = new DuckDogeSkins(PRICE, SKIN_COUNT, "ipfs://duck-doge/{id}.json", owner);
        vm.deal(player, 10 ether);
        vm.deal(owner, 1 ether);

        assertEq(skins.MINT_PRICE(), PRICE);
        assertEq(skins.skinCount(), SKIN_COUNT);
        assertEq(skins.owner(), owner);
        assertFalse(skins.paused());
    }

    function test_constructor_revertsOnZeroPrice() public {
        vm.expectRevert(DuckDogeSkins.ZeroMintPrice.selector);
        new DuckDogeSkins(0, SKIN_COUNT, "", owner);
    }

    function test_constructor_revertsOnZeroSkinCount() public {
        vm.expectRevert(DuckDogeSkins.ZeroSkinCount.selector);
        new DuckDogeSkins(PRICE, 0, "", owner);
    }

    function test_mint_success_updatesBalanceAndEmits() public {
        uint256 before = player.balance;

        vm.prank(player);
        vm.expectEmit(true, true, true, true, address(skins));
        emit TransferSingle(player, address(0), player, 1, 2);
        skins.mint{value: PRICE * 2}(1, 2);

        assertEq(player.balance, before - PRICE * 2);
        assertEq(address(skins).balance, PRICE * 2);
        assertEq(skins.balanceOf(player, 1), 2);
        assertEq(skins.balanceOf(player, 0), 0);
    }

    function test_mint_ownerPaysTheSamePrice() public {
        uint256 before = owner.balance;

        vm.prank(owner);
        skins.mint{value: PRICE}(0, 1);

        assertEq(skins.balanceOf(owner, 0), 1);
        assertEq(owner.balance, before - PRICE);
        assertEq(address(skins).balance, PRICE);
    }

    function test_mint_revertsOnUnderpayment() public {
        _expectPaymentRevert(player, 0, 1, PRICE - 1);
    }

    function test_mint_revertsOnOverpayment() public {
        _expectPaymentRevert(player, SKIN_COUNT - 1, 1, PRICE + 1);
    }

    function test_mint_revertsOnZeroPayment() public {
        _expectPaymentRevert(player, 0, 2, 0);
    }

    function test_mint_revertsOnZeroAmount() public {
        uint256 before = player.balance;

        vm.prank(player);
        vm.expectRevert(DuckDogeSkins.ZeroAmount.selector);
        skins.mint{value: 0}(0, 0);

        vm.prank(player);
        vm.expectRevert(DuckDogeSkins.ZeroAmount.selector);
        skins.mint{value: PRICE}(0, 0);

        assertEq(player.balance, before);
        assertEq(address(skins).balance, 0);
        assertEq(skins.balanceOf(player, 0), 0);
    }

    function test_mint_revertsOnInvalidSkin() public {
        uint256 before = player.balance;

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(DuckDogeSkins.InvalidSkin.selector, SKIN_COUNT));
        skins.mint{value: PRICE}(SKIN_COUNT, 1);

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(DuckDogeSkins.InvalidSkin.selector, type(uint256).max));
        skins.mint{value: PRICE}(type(uint256).max, 1);

        assertEq(player.balance, before);
        assertEq(address(skins).balance, 0);
    }

    function test_mint_revertsOnPaymentOverflow() public {
        uint256 amount = type(uint256).max / PRICE + 1;
        uint256 before = player.balance;

        vm.prank(player);
        vm.expectRevert(stdError.arithmeticError);
        skins.mint{value: 0}(0, amount);

        assertEq(player.balance, before);
        assertEq(skins.balanceOf(player, 0), 0);
    }

    function test_mint_revertsWhenPaused() public {
        vm.prank(owner);
        skins.pause();

        vm.prank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        skins.mint{value: PRICE}(0, 1);

        vm.prank(player);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        skins.mint{value: PRICE}(1, 1);

        assertEq(skins.balanceOf(owner, 0), 0);
        assertEq(skins.balanceOf(player, 1), 0);
        assertEq(address(skins).balance, 0);
    }

    function test_pauseAndUnpause() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player));
        skins.pause();
        assertFalse(skins.paused());

        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(skins));
        emit Paused(owner);
        skins.pause();
        assertTrue(skins.paused());

        vm.prank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        skins.pause();

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player));
        skins.unpause();
        assertTrue(skins.paused());

        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(skins));
        emit Unpaused(owner);
        skins.unpause();
        assertFalse(skins.paused());

        vm.prank(owner);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        skins.unpause();

        vm.prank(player);
        skins.mint{value: PRICE}(3, 1);
        assertEq(skins.balanceOf(player, 3), 1);
    }

    function test_unpause_revertsWhenNotPaused() public {
        vm.prank(owner);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        skins.unpause();
    }

    function test_withdraw_transfersExactBalance() public {
        uint256 ownerStart = owner.balance;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(skins));
        emit Withdrawn(owner, 0);
        skins.withdraw();
        assertEq(owner.balance, ownerStart);
        assertEq(address(skins).balance, 0);

        _mintSkin(player, 0, 1);
        _mintSkin(player, 2, 4);
        uint256 expected = PRICE * 5;
        assertEq(address(skins).balance, expected);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(skins));
        emit Withdrawn(owner, expected);
        skins.withdraw();

        assertEq(address(skins).balance, 0);
        assertEq(owner.balance, ownerStart + expected);

        vm.prank(owner);
        skins.withdraw();
        assertEq(owner.balance, ownerStart + expected);
        assertEq(address(skins).balance, 0);
    }

    function test_withdraw_revertsForNonOwner() public {
        _mintSkin(player, 1, 2);
        uint256 stuck = address(skins).balance;
        uint256 playerBefore = player.balance;

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player));
        skins.withdraw();

        assertEq(address(skins).balance, stuck);
        assertEq(player.balance, playerBefore);
    }

    function test_withdraw_revertsWhenOwnerRejects() public {
        RejectingOwner rejector = new RejectingOwner();
        DuckDogeSkins local = new DuckDogeSkins(PRICE, SKIN_COUNT, "", address(rejector));

        vm.prank(player);
        local.mint{value: PRICE * 3}(0, 3);
        uint256 stuck = address(local).balance;
        assertEq(stuck, PRICE * 3);

        vm.expectRevert(DuckDogeSkins.WithdrawFailed.selector);
        rejector.withdrawSkins(local);

        assertEq(address(local).balance, stuck);
        assertEq(address(rejector).balance, 0);
        assertEq(local.balanceOf(player, 0), 3);
    }

    function test_balancesOf_listsEverySkin() public {
        _mintSkin(player, 0, 1);
        _mintSkin(player, SKIN_COUNT - 1, 2);

        uint256[] memory owned = skins.balancesOf(player);
        assertEq(owned.length, SKIN_COUNT);
        assertEq(owned[0], 1);
        assertEq(owned[1], 0);
        assertEq(owned[2], 0);
        assertEq(owned[SKIN_COUNT - 1], 2);

        uint256[] memory empty = skins.balancesOf(makeAddr("empty"));
        assertEq(empty.length, SKIN_COUNT);
        assertEq(empty[0], 0);
        assertEq(empty[1], 0);
        assertEq(empty[2], 0);
        assertEq(empty[3], 0);

        vm.prank(owner);
        skins.pause();
        uint256[] memory whilePaused = skins.balancesOf(player);
        assertEq(whilePaused[0], 1);
        assertEq(whilePaused[SKIN_COUNT - 1], 2);
    }

    function _mintSkin(address account, uint256 skinId, uint256 amount) internal {
        vm.prank(account);
        skins.mint{value: PRICE * amount}(skinId, amount);
    }

    function _expectPaymentRevert(address account, uint256 skinId, uint256 amount, uint256 value) internal {
        uint256 before = account.balance;
        uint256 expected = PRICE * amount;

        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(DuckDogeSkins.IncorrectPayment.selector, expected, value));
        skins.mint{value: value}(skinId, amount);

        assertEq(account.balance, before);
        assertEq(address(skins).balance, 0);
        assertEq(skins.balanceOf(account, skinId), 0);
    }
}
