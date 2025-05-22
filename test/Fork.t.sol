// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@bananapus/721-hook/script/helpers/Hook721DeploymentLib.sol";
import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";
import "@bananapus/suckers/script/helpers/SuckerDeploymentLib.sol";

import "./../src/CTDeployer.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers/src/structs/JBSuckerDeployerConfig.sol";
import {JBTokenMapping} from "@bananapus/suckers/src/structs/JBTokenMapping.sol";
import {CTProjectOwner} from "./../src/CTProjectOwner.sol";
import {CTPublisher} from "./../src/CTPublisher.sol";

import "forge-std/Test.sol";

contract ForkTest is Test {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the deployment of the 721 hook contracts for the chain we are deploying to.
    Hook721Deployment hook;
    /// @notice tracks the deployment of the sucker contracts for the chain we are deploying to.
    SuckerDeployment suckers;

    CTPublisher publisher;
    CTDeployer deployer;

    address TRUSTED_FORWARDER;

    function setUp() public {
        // Fork ETH mainnet.
        vm.createSelectFork("https://ethereum-rpc.publicnode.com", 22_432_742);

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

        // Deploy the croptop contracts.
        publisher = new CTPublisher(core.controller, core.permissions, 1, TRUSTED_FORWARDER);
        deployer =
            new CTDeployer(core.controller, hook.project_deployer, publisher, suckers.registry, TRUSTED_FORWARDER);
    }

    function testDeployProject(address owner) public {
        vm.assume(owner != address(0) && owner.code.length == 0);

        // Create the project config.
        CTProjectConfig memory config = CTProjectConfig({
            terminalConfigurations: new JBTerminalConfig[](0),
            projectUri: "https://croptop.eth.sucks/",
            allowedPosts: new CTDeployerAllowedPost[](0),
            contractUri: "https://croptop.eth.sucks/",
            name: "Croptop",
            symbol: "CROP",
            salt: bytes32(0)
        });

        CTSuckerDeploymentConfig memory suckerConfig =
            CTSuckerDeploymentConfig({deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: bytes32(0)});

        deployer.deployProjectFor(owner, config, suckerConfig);
    }

    function testDeployProjectWithSuckers(address owner, bytes32 salt, bytes32 suckerSalt) public {
        vm.assume(owner != address(0) && owner.code.length == 0);
        vm.assume(suckerSalt != bytes32(0));

        // Create the project config.
        CTProjectConfig memory config = CTProjectConfig({
            terminalConfigurations: new JBTerminalConfig[](0),
            projectUri: "https://croptop.eth.sucks/",
            allowedPosts: new CTDeployerAllowedPost[](0),
            contractUri: "https://croptop.eth.sucks/",
            name: "Croptop",
            symbol: "CROP",
            salt: salt
        });

        // Create the sucker config.
        JBTokenMapping[] memory tokens = new JBTokenMapping[](1);
        tokens[0] = JBTokenMapping({
            localToken: address(JBConstants.NATIVE_TOKEN),
            minGas: 200_000,
            remoteToken: address(JBConstants.NATIVE_TOKEN),
            minBridgeAmount: 0.001 ether
        });

        JBSuckerDeployerConfig[] memory deployerConfigurations = new JBSuckerDeployerConfig[](1);
        deployerConfigurations[0] = JBSuckerDeployerConfig({deployer: suckers.optimismDeployer, mappings: tokens});

        CTSuckerDeploymentConfig memory suckerConfig =
            CTSuckerDeploymentConfig({deployerConfigurations: deployerConfigurations, salt: suckerSalt});

        // Deploy the project.
        (uint256 projectId,) = deployer.deployProjectFor(owner, config, suckerConfig);

        // Check that the projectId has a sucker.
        assertEq(suckers.registry.suckersOf(projectId).length, deployerConfigurations.length);
    }
}
