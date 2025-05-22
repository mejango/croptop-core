// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookProjectDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookProjectDeployer.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";

import {ICTPublisher} from "./ICTPublisher.sol";
import {CTDeployerAllowedPost} from "../structs/CTDeployerAllowedPost.sol";
import {CTSuckerDeploymentConfig} from "../structs/CTSuckerDeploymentConfig.sol";
import {CTProjectConfig} from "../structs/CTProjectConfig.sol";

interface ICTDeployer {
    function CONTROLLER() external view returns (IJBController);
    function DEPLOYER() external view returns (IJB721TiersHookProjectDeployer);
    function PUBLISHER() external view returns (ICTPublisher);

    function deployProjectFor(
        address owner,
        CTProjectConfig calldata projectConfigurations,
        CTSuckerDeploymentConfig calldata deployerConfigurations
    )
        external
        returns (uint256 projectId, IJB721TiersHook hook);

    function deploySuckersFor(
        uint256 projectId,
        CTSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        external
        returns (address[] memory suckers);
}
