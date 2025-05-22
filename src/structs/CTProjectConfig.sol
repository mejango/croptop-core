// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {CTDeployerAllowedPost} from "../structs/CTDeployerAllowedPost.sol";

/// @param terminalConfigurations The terminals that the network uses to accept payments through.
/// @param projectUri The metadata URI containing project info.
/// @param allowedPosts The type of posts that the project should allow.
/// @param contractUri A link to the collection's metadata.
/// @param name The name of the collection where posts will go.
/// @param symbol The symbol of the collection where posts will go.
/// @param salt A salt to use for the deterministic deployment.
struct CTProjectConfig {
    JBTerminalConfig[] terminalConfigurations;
    string projectUri;
    CTDeployerAllowedPost[] allowedPosts;
    string contractUri;
    string name;
    string symbol;
    bytes32 salt;
}
