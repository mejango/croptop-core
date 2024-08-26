// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";

import {ICTPublisher} from "./ICTPublisher.sol";

interface ICTProjectOwner {
    function PERMISSIONS() external view returns (IJBPermissions);
    function PROJECTS() external view returns (IJBProjects);
    function PUBLISHER() external view returns (ICTPublisher);
}
