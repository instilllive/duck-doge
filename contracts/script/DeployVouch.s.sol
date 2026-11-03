// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DuckDogeSkins} from "../src/DuckDogeSkins.sol";
import {DuckDogeVouch} from "../src/DuckDogeVouch.sol";

/// @notice Deploys DuckDogeVouch. The broadcaster is whoever `forge script`
///         was given on the CLI (`--account`, `--ledger`, or `--interactive`).
///         This file does not read a private key from the environment or disk.
/// @dev The README command pins DogeOS Chikyū Testnet. The chain-id check
///      refuses any other network, including mainnet. Simulate without
///      `--broadcast` before sending anything.
contract DeployVouch is Script {
    uint256 internal constant DOGEOS_CHIKYU_TESTNET = 6281971;

    /// @dev Testnet cosmetic price: 0.01 DOGE. DogeOS DOGE uses 18 decimals.
    uint256 internal constant TESTNET_MINT_PRICE = 0.01 ether;

    /// @dev Paid ids 0..7. Earned ids 8..11, minted only by the vouch contract.
    uint256 internal constant TESTNET_PAID_SKINS = 8;
    uint256 internal constant TESTNET_EARNED_SKINS = 4;

    /// @dev Placeholder metadata URI. The contracts have no setter.
    string internal constant TESTNET_URI = "https://duck-doge.example/skins/{id}.json";

    function run() external {
        require(block.chainid == DOGEOS_CHIKYU_TESTNET, "DuckDogeVouch: DogeOS Chikyu testnet only");

        vm.startBroadcast();
        DuckDogeSkins deployedSkins =
            new DuckDogeSkins(TESTNET_MINT_PRICE, TESTNET_PAID_SKINS, TESTNET_EARNED_SKINS, TESTNET_URI, msg.sender);
        DuckDogeVouch deployed = new DuckDogeVouch(deployedSkins);
        deployedSkins.setMinter(address(deployed));
        vm.stopBroadcast();

        console2.log("DuckDogeSkins", address(deployedSkins));
        console2.log("DuckDogeVouch", address(deployed));
        console2.log("minter", deployedSkins.minter());
        console2.log("chainId", block.chainid);
        console2.log("Paste both addresses into web/src/config.js.");
    }
}
