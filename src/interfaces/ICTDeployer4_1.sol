// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";

import {ICTPublisher4_1} from "./ICTPublisher4_1.sol";
import {CTSuckerDeploymentConfig} from "../structs/CTSuckerDeploymentConfig.sol";
import {CTProjectConfig} from "../structs/CTProjectConfig.sol";

interface ICTDeployer4_1 {
    function PROJECTS() external view returns (IJBProjects);
    function DEPLOYER() external view returns (IJB721TiersHookDeployer);
    function PUBLISHER() external view returns (ICTPublisher4_1);

    function deployProjectFor(
        address owner,
        CTProjectConfig calldata projectConfigurations,
        CTSuckerDeploymentConfig calldata deployerConfigurations,
        IJBController controller
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
