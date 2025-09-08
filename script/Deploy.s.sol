// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BlockAnomalyResponse} from "../src/BlockAnomalyResponse.sol";
import {BlockTimeAnomalyTrap} from "../src/BlockTimeAnomalyTrap.sol";

/**
 * @title Deployment Script for Block Time Anomaly Trap
 * @notice Foundry script to deploy both response contract and trap contract
 */
contract DeployScript is Script {

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying with address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy response contract first
        console.log("Deploying BlockAnomalyResponse...");
        BlockAnomalyResponse responseContract = new BlockAnomalyResponse();
        console.log("BlockAnomalyResponse deployed at:", address(responseContract));

        // Deploy trap contract
        console.log("Deploying BlockTimeAnomalyTrap...");
        BlockTimeAnomalyTrap trapContract = new BlockTimeAnomalyTrap();
        console.log("BlockTimeAnomalyTrap deployed at:", address(trapContract));

        // Authorize the trap on the response contract
        console.log("Authorizing trap on response contract...");
        responseContract.authorizeTrap(address(trapContract));
        console.log("Trap authorized successfully");

        vm.stopBroadcast();

        // Print deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Response Contract:", address(responseContract));
        console.log("Trap Contract:", address(trapContract));
        console.log("Deployer:", deployer);
        console.log("Network: Hoodi Testnet (Chain ID: 560048)");

        // Print next steps
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Update drosera.toml with response contract address:");
        console.log("   response_contract =", vm.toString(address(responseContract)));
        console.log("2. Deploy to Drosera: DROSERA_PRIVATE_KEY=xxx drosera apply");
        console.log("3. Update README.md with deployed addresses");
    }
}
