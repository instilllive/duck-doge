// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title DuckDogeSkins
/// @notice Cosmetic ERC-1155 skins for the duck doge testnet game.
/// @dev Paid ids are `[0, skinCount)`. `MINT_PRICE` and that id set are fixed
///      in the constructor. Earned ids are `[skinCount, skinCount + earnedSkinCount)`.
///      Only `minter` can mint those, one at a time and for free. `setMinter`
///      can be called once and never changed, so the owner has no later path
///      to mint earned skins or to point the minter at themselves.
///      There is no proxy, no upgrade path, and no price setter.
contract DuckDogeSkins is ERC1155, Ownable, Pausable {
    /// @notice Exact price, in wei, of one paid skin. Testnet DOGE uses 18 decimals.
    uint256 public immutable MINT_PRICE;

    /// @notice Number of paid skin ids. Valid paid ids are `0 .. skinCount - 1`.
    uint256 public immutable skinCount;

    /// @notice Number of earned skin ids. Index `i` is token id `skinCount + i`.
    uint256 public immutable earnedSkinCount;

    /// @notice The only address allowed to mint earned skins. Zero until set.
    address public minter;

    event Withdrawn(address indexed to, uint256 amount);
    event MinterSet(address indexed minter);

    error ZeroMintPrice();
    error ZeroSkinCount();
    error ZeroAmount();
    error InvalidSkin(uint256 skinId);
    error IncorrectPayment(uint256 expected, uint256 sent);
    error WithdrawFailed();
    error MinterAlreadySet();
    error ZeroMinter();
    error NotMinter(address caller);
    error InvalidEarnedSkin(uint256 earnedIndex);

    constructor(
        uint256 mintPrice,
        uint256 skinCount_,
        uint256 earnedSkinCount_,
        string memory uri_,
        address initialOwner
    ) ERC1155(uri_) Ownable(initialOwner) {
        if (mintPrice == 0) revert ZeroMintPrice();
        if (skinCount_ == 0) revert ZeroSkinCount();
        MINT_PRICE = mintPrice;
        skinCount = skinCount_;
        earnedSkinCount = earnedSkinCount_;
    }

    /// @notice Mint `amount` of a paid `skinId` to the caller. `msg.value` must equal `MINT_PRICE * amount`.
    /// @dev Earned ids are rejected here. They are not for sale.
    function mint(uint256 skinId, uint256 amount) external payable whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (skinId >= skinCount) revert InvalidSkin(skinId);
        uint256 cost = MINT_PRICE * amount;
        if (msg.value != cost) revert IncorrectPayment(cost, msg.value);
        _mint(msg.sender, skinId, amount, "");
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Send the contract's full balance to the owner.
    function withdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        address to = owner();
        (bool success,) = to.call{value: amount}("");
        if (!success) revert WithdrawFailed();
        emit Withdrawn(to, amount);
    }

    /// @notice Point earned mints at `minter_`. Callable once, by the owner, and never again.
    /// @dev After this returns, the owner cannot mint earned skins and cannot replace the minter.
    function setMinter(address minter_) external onlyOwner {
        if (minter != address(0)) revert MinterAlreadySet();
        if (minter_ == address(0)) revert ZeroMinter();
        minter = minter_;
        emit MinterSet(minter_);
    }

    /// @notice Mint one earned skin to `to`. `earnedIndex` is `0 .. earnedSkinCount - 1`.
    /// @dev Not pausable. The owner of this contract must not be able to freeze vouches
    ///      by pausing the shop. The token id is `skinCount + earnedIndex`.
    function mintEarned(address to, uint256 earnedIndex) external {
        if (msg.sender != minter) revert NotMinter(msg.sender);
        if (earnedIndex >= earnedSkinCount) revert InvalidEarnedSkin(earnedIndex);
        _mint(to, skinCount + earnedIndex, 1, "");
    }

    /// @notice Balance of every paid skin for `wallet`. Index `i` is the balance of skin id `i`.
    function balancesOf(address wallet) external view returns (uint256[] memory balances) {
        uint256 count = skinCount;
        balances = new uint256[](count);
        for (uint256 skinId = 0; skinId < count; ++skinId) {
            balances[skinId] = balanceOf(wallet, skinId);
        }
    }

    /// @notice Balance of every earned skin for `wallet`. Index `i` is token id `skinCount + i`.
    function earnedBalancesOf(address wallet) external view returns (uint256[] memory balances) {
        uint256 count = earnedSkinCount;
        balances = new uint256[](count);
        for (uint256 earnedIndex = 0; earnedIndex < count; ++earnedIndex) {
            balances[earnedIndex] = balanceOf(wallet, skinCount + earnedIndex);
        }
    }
}
