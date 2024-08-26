// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJB721TiersHookProjectDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookProjectDeployer.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";

import {ICTPublisher} from "./ICTPublisher.sol";
import {CTAllowedPost} from "../structs/CTAllowedPost.sol";

interface ICTDeployer {
  function CONTROLLER() external view returns (IJBController);
  function DEPLOYER() external view returns (IJB721TiersHookProjectDeployer);
  function PUBLISHER() external view returns (ICTPublisher);

  function deployProjectFor(
        address owner,
        JBTerminalConfig[] calldata terminalConfigurations,
        string memory projectUri,
        CTAllowedPost[] calldata allowedPosts,
        string memory contractUri,
        string memory name,
        string memory symbol
    )
        external
        returns (uint256 projectId);
}

