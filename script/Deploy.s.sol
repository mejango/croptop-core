// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";
import "@bananapus/721-hook/script/helpers/Hook721DeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import {CTPublisher} from "./../src/CTPublisher.sol";
import {CTDeployer} from "./../src/CTDeployer.sol";
import {CTProjectOwner} from "./../src/CTProjectOwner.sol";

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the deployment of the 721 hook contracts for the chain we are deploying to.
    Hook721Deployment hook;

    uint256 FEE_PROJECT_ID = 1;

    /// @notice the salts that are used to deploy the contracts.
    bytes32 PUBLISHER_SALT = "CTPublisher";
    bytes32 DEPLOYER_SALT = "CTDeployer";
    bytes32 PROJECT_OWNER_SALT = "CTProjectOwner";

    function configureSphinx() public override {
        // TODO: Update to contain croptop devs.
        sphinxConfig.owners = [0x26416423d530b1931A2a7a6b7D435Fac65eED27d];
        sphinxConfig.orgId = "cltepuu9u0003j58rjtbd0hvu";
        sphinxConfig.projectName = "croptop-core";
        sphinxConfig.threshold = 1;
        sphinxConfig.mainnets = ["ethereum", "optimism", "polygon"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "polygon_mumbai"];
        sphinxConfig.saltNonce = 4;
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core/deployments/"))
        );
        // Get the deployment addresses for the 721 hook contracts for this chain.
        hook = Hook721DeploymentLib.getDeployment(
            vm.envOr("NANA_721_DEPLOYMENT_PATH", string("node_modules/@bananapus/721-hook/deployments/"))
        );
        // Perform the deployment transactions.
        deploy();
    }

    function deploy() public sphinx {
        CTPublisher publisher = new CTPublisher{salt: PUBLISHER_SALT}(
            core.controller, core.permissions, FEE_PROJECT_ID
        );

        new CTDeployer{salt: DEPLOYER_SALT}(
            core.controller,
            hook.project_deployer,
            publisher
        );

        new CTProjectOwner{salt: PROJECT_OWNER_SALT}(
            core.permissions, core.projects, publisher
        );
    }
}
