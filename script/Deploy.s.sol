// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/721-hook/script/helpers/Hook721DeploymentLib.sol";
import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";
import "@bananapus/suckers/script/helpers/SuckerDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import {CTDeployer} from "./../src/CTDeployer.sol";
import {CTProjectOwner} from "./../src/CTProjectOwner.sol";
import {CTPublisher} from "./../src/CTPublisher.sol";

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the deployment of the 721 hook contracts for the chain we are deploying to.
    Hook721Deployment hook;
    /// @notice tracks the deployment of the sucker contracts for the chain we are deploying to.
    SuckerDeployment suckers;

    // @notice set this to a non-zero value to re-use an existing projectID. Having it set to 0 will deploy a new
    // fee_project.
    uint256 FEE_PROJECT_ID = 0;

    /// @notice the salts that are used to deploy the contracts.
    bytes32 PUBLISHER_SALT = "_PUBLISHER_SALT_";
    bytes32 DEPLOYER_SALT = "_DEPLOYER_SALT_";
    bytes32 PROJECT_OWNER_SALT = "_PROJECT_OWNER_SALT_";
    address TRUSTED_FORWARDER;

    function configureSphinx() public override {
        // TODO: Update to contain croptop devs.
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
        // If the fee project id is 0, then we want to deploy a new fee project.
        if (FEE_PROJECT_ID == 0) {
            FEE_PROJECT_ID = core.projects.createFor(safeAddress());
        }

        CTPublisher publisher;
        {
            // Perform the check for the publisher.
            (address _publisher, bool _publisherIsDeployed) = _isDeployed(
                PUBLISHER_SALT,
                type(CTPublisher).creationCode,
                abi.encode(core.controller, core.permissions, FEE_PROJECT_ID, TRUSTED_FORWARDER)
            );

            // Deploy it if it has not been deployed yet.
            publisher = !_publisherIsDeployed
                ? new CTPublisher{salt: PUBLISHER_SALT}(
                    core.controller, core.permissions, FEE_PROJECT_ID, TRUSTED_FORWARDER
                )
                : CTPublisher(_publisher);
        }

        CTDeployer deployer;
        {
            // Perform the check for the publisher.
            (address _deployer, bool _deployerIsDeployed) = _isDeployed(
                DEPLOYER_SALT,
                type(CTDeployer).creationCode,
                abi.encode(core.controller, hook.project_deployer, publisher, suckers.registry, TRUSTED_FORWARDER)
            );

            // Deploy it if it has not been deployed yet.
            deployer = !_deployerIsDeployed
                ? new CTDeployer{salt: DEPLOYER_SALT}(
                    core.controller, hook.project_deployer, publisher, suckers.registry, TRUSTED_FORWARDER
                )
                : CTDeployer(_deployer);
        }

        CTProjectOwner owner;
        {
            // Perform the check for the publisher.
            (address _owner, bool _ownerIsDeployed) = _isDeployed(
                PROJECT_OWNER_SALT,
                type(CTProjectOwner).creationCode,
                abi.encode(core.permissions, core.projects, publisher)
            );

            // Deploy it if it has not been deployed yet.
            owner = !_ownerIsDeployed
                ? new CTProjectOwner{salt: PROJECT_OWNER_SALT}(core.permissions, core.projects, publisher)
                : CTProjectOwner(_owner);
        }
    }

    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (address, bool)
    {
        address _deployedTo = vm.computeCreate2Address({
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)),
            // Arachnid/deterministic-deployment-proxy address.
            deployer: address(0x4e59b44847b379578588920cA78FbF26c0B4956C)
        });

        // Return if code is already present at this address.
        return (_deployedTo, address(_deployedTo).code.length != 0);
    }
}
