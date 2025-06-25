// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/721-hook/script/helpers/Hook721DeploymentLib.sol";
import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";
import "@bananapus/suckers/script/helpers/SuckerDeploymentLib.sol";
import "./helpers/CroptopDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import {CTDeployer4_1} from "./../src/CTDeployer4_1.sol";
import {CTPublisher4_1} from "./../src/CTPublisher4_1.sol";

contract Deploy41Script is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the deployment of the 721 hook contracts for the chain we are deploying to.
    Hook721Deployment hook;
    /// @notice tracks the deployment of the sucker contracts for the chain we are deploying to.
    SuckerDeployment suckers;
    /// @notice tracks the latest croptop deployment.
    CroptopDeployment croptop;

    // @notice set this to a non-zero value to re-use an existing projectID. Having it set to 0 will deploy a new
    // fee_project.
    uint256 FEE_PROJECT_ID = 2;

    /// @notice the salts that are used to deploy the contracts.
    bytes32 PUBLISHER_SALT = "_PUBLISHER_SALT_";
    bytes32 DEPLOYER_SALT = "_DEPLOYER_SALT_";
    bytes32 PROJECT_OWNER_SALT = "_PROJECT_OWNER_SALT_";
    address TRUSTED_FORWARDER;

    function configureSphinx() public override {
        sphinxConfig.projectName = "croptop-core";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core/deployments/"))
        );
        // Get the deployment addresses for the croptop contracts for this chain.
        croptop = CroptopDeploymentLib.getDeployment(vm.envOr("CROPTOP_DEPLOYMENT_PATH", string("deployments/")));
        // Get the deployment addresses for the 721 hook contracts for this chain.
        hook = Hook721DeploymentLib.getDeployment(
            vm.envOr("NANA_721_DEPLOYMENT_PATH", string("node_modules/@bananapus/721-hook/deployments/"))
        );
        // Get the deployment addresses for the suckers contracts for this chain.
        suckers = SuckerDeploymentLib.getDeployment(
            vm.envOr("NANA_SUCKERS_DEPLOYMENT_PATH", string("node_modules/@bananapus/suckers/deployments/"))
        );

        // We use the same trusted forwarder as the core deployment.
        TRUSTED_FORWARDER = core.controller.trustedForwarder();

        // Perform the deployment transactions.
        deploy();
    }

    function deploy() public sphinx {
        CTPublisher4_1 publisher = new CTPublisher4_1{salt: PUBLISHER_SALT}(
            core.directory, core.permissions, FEE_PROJECT_ID, TRUSTED_FORWARDER
        );

        new CTDeployer4_1{salt: DEPLOYER_SALT}(
            core.permissions, core.projects, hook.hook_deployer, publisher, suckers.registry, TRUSTED_FORWARDER
        );
    }
}
