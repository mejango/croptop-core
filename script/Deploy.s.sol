// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBPermissioned} from "@bananapus/core/src/interfaces/IJBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {JB721TiersHookProjectDeployer} from "@bananapus/721-hook/src/JB721TiersHookProjectDeployer.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook/src/JB721TiersHookStore.sol";

import {CTPublisher} from "./../src/CTPublisher.sol";
import {CTDeployer} from "./../src/CTDeployer.sol";
import {CTProjectOwner} from "./../src/CTProjectOwner.sol";

contract Deploy is Script {
    uint256 FEE_PROJECT_ID = 1;

    function run() public {
        uint256 chainId = block.chainid;
        string memory chain;

        // Ethereum Mainnet
        if (chainId == 1) {
            chain = "1";
            // Ethereum Sepolia
        } else if (chainId == 11_155_111) {
            chain = "11155111";
            // Optimism Mainnet
        } else if (chainId == 420) {
            chain = "420";
            // Optimism Sepolia
        } else if (chainId == 11_155_420) {
            chain = "11155420";
            // Polygon Mainnet
        } else if (chainId == 137) {
            chain = "137";
            // Polygon Mumbai
        } else if (chainId == 80_001) {
            chain = "80001";
        } else {
            revert("Invalid RPC / no juice contracts deployed on this network");
        }

        address controllerAddress = _getDeploymentAddress(
            string.concat("node_modules/@bananapus/core/broadcast/Deploy.s.sol/", chain, "/run-latest.json"), "JBController"
        );

        address deployerAddress = _getDeploymentAddress(
            string.concat("node_modules/@bananapus/721-hook/broadcast/Deploy.s.sol/", chain, "/run-latest.json"),
            "JB721TiersHookProjectDeployer"
        );

        address storeAddress = _getDeploymentAddress(
            string.concat("node_modules/@bananapus/721-hook/broadcast/Deploy.s.sol/", chain, "/run-latest.json"),
            "JB721TiersHookStore"
        );

        vm.startBroadcast();
        CTPublisher publisher = new CTPublisher(
            IJBController(controllerAddress), IJBPermissioned(controllerAddress).PERMISSIONS(), FEE_PROJECT_ID
        );
        new CTDeployer(
            IJBController(controllerAddress),
            JB721TiersHookProjectDeployer(deployerAddress),
            JB721TiersHookStore(storeAddress),
            publisher
        );
        new CTProjectOwner(
            IJBPermissioned(controllerAddress).PERMISSIONS(), IJBController(controllerAddress).PROJECTS(), publisher
        );
        vm.stopBroadcast();
    }

    /// @notice Get the address of a contract that was deployed by the Deploy script.
    /// @dev Reverts if the contract was not found.
    /// @param path The path to the deployment file.
    /// @param contractName The name of the contract to get the address of.
    /// @return The address of the contract.
    function _getDeploymentAddress(string memory path, string memory contractName) internal view returns (address) {
        string memory deploymentJson = vm.readFile(path);
        uint256 nOfTransactions = stdJson.readStringArray(deploymentJson, ".transactions").length;

        for (uint256 i = 0; i < nOfTransactions; i++) {
            string memory currentKey = string.concat(".transactions", "[", Strings.toString(i), "]");
            string memory currentContractName =
                stdJson.readString(deploymentJson, string.concat(currentKey, ".contractName"));

            if (keccak256(abi.encodePacked(currentContractName)) == keccak256(abi.encodePacked(contractName))) {
                return stdJson.readAddress(deploymentJson, string.concat(currentKey, ".contractAddress"));
            }
        }

        revert(string.concat("Could not find contract with name '", contractName, "' in deployment file '", path, "'"));
    }
}
