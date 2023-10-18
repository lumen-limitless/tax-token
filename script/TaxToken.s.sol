// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {TaxToken} from "src/TaxToken.sol";
import "forge-std/Script.sol";

contract TaxTokenScript is Script {
    address owner = vm.envAddress("OWNER");
    uint256 fee = 300;
    address feeRecipient = vm.envAddress("FEE_RECIPIENT");
    uint256 initialSupply = 1_000_000_000_000e18; // 1 trillion
    string name = vm.envString("TOKEN_NAME");
    string symbol = vm.envString("TOKEN_SYMBOL");

    function run() external returns (TaxToken deployment) {
        console.log("Running TaxTokenScript");
        console.log("owner: %s", owner);
        console.log("fee: %s", fee);
        console.log("feeRecipient: %s", feeRecipient);
        console.log("initialSupply: %s", initialSupply);
        console.log("name: %s", name);
        console.log("symbol: %s", symbol);

        vm.startBroadcast();

        deployment = new TaxToken(owner, fee, feeRecipient, initialSupply, name, symbol);

        vm.stopBroadcast();
    }
}
