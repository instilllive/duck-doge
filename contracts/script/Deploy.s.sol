// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DuckDogeSkins} from "../src/DuckDogeSkins.sol";

/// @notice Deploys DuckDogeSkins. The broadcaster is whoever `forge script`
///         was given on the CLI (`--account`, `--ledger`, or `--interactive`).
///         This file does not read a private key from the environment or disk.
/// @dev The README command pins DogeOS Chikyū Testnet. Simulate without
///      `--broadcast` before sending anything.
contract Deploy is Script {
    /// @dev Testnet cosmetic price: 0.01 DOGE. DogeOS DOGE uses 18 decimals.
    uint256 internal constant TESTNET_MINT_PRICE = 0.01 ether;

    /// @dev Skin ids for this deployment are 0..7.
    uint256 internal constant TESTNET_SKIN_COUNT = 8;

    /// @dev Placeholder metadata URI. Change this constant in the script
    ///      before broadcasting if the host changes. The contract has no setter.
    string internal constant TESTNET_URI = "https://duck-doge.example/skins/{id}.json";

    function run() external {
        vm.startBroadcast();
        DuckDogeSkins skins = new DuckDogeSkins(TESTNET_MINT_PRICE, TESTNET_SKIN_COUNT, TESTNET_URI, msg.sender);
        vm.stopBroadcast();

        console2.log("DuckDogeSkins", address(skins));
        console2.log("owner", skins.owner());
        console2.log("mintPrice", skins.MINT_PRICE());
        console2.log("skinCount", skins.skinCount());
    }
}
