// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title DuckDogeSkins
/// @notice Cosmetic ERC-1155 skins for the duck doge testnet game.
/// @dev Skin ids are the closed range `[0, skinCount)`. `MINT_PRICE` and that
///      id set are fixed in the constructor. There is no proxy, no upgrade
///      path, no admin mint, and no price setter.
contract DuckDogeSkins is ERC1155, Ownable, Pausable {
    /// @notice Exact price, in wei, of one skin. Testnet DOGE uses 18 decimals.
    uint256 public immutable MINT_PRICE;

    /// @notice Number of skin ids. Valid ids are `0 .. skinCount - 1`.
    uint256 public immutable skinCount;

    event Withdrawn(address indexed to, uint256 amount);

    error ZeroMintPrice();
    error ZeroSkinCount();
    error ZeroAmount();
    error InvalidSkin(uint256 skinId);
    error IncorrectPayment(uint256 expected, uint256 sent);
    error WithdrawFailed();

    constructor(uint256 mintPrice, uint256 skinCount_, string memory uri_, address initialOwner)
        ERC1155(uri_)
        Ownable(initialOwner)
    {
        if (mintPrice == 0) revert ZeroMintPrice();
        if (skinCount_ == 0) revert ZeroSkinCount();
        MINT_PRICE = mintPrice;
        skinCount = skinCount_;
    }

    /// @notice Mint `amount` of `skinId` to the caller. `msg.value` must equal `MINT_PRICE * amount`.
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

    /// @notice Balance of every skin for `wallet`. Index `i` is the balance of skin id `i`.
    function balancesOf(address wallet) external view returns (uint256[] memory balances) {
        uint256 count = skinCount;
        balances = new uint256[](count);
        for (uint256 skinId = 0; skinId < count; ++skinId) {
            balances[skinId] = balanceOf(wallet, skinId);
        }
    }
}
