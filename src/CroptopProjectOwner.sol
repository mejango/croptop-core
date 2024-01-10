// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC721Receiver } from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import { IJBPermissions } from "lib/juice-contracts-v4/src/interfaces/IJBPermissions.sol";
import { IJBProjects } from "lib/juice-contracts-v4/src/interfaces/IJBProjects.sol";
import { JBPermissions } from "lib/juice-contracts-v4/src/structs/JBOperatorData.sol";
import { JB721PermissionIds } from "lib/juice-721-hook/src/libraries/JB721PermissionIds.sol";
import { CroptopPublisher } from "./CroptopPublisher.sol";

/// @notice A contract that can be sent a project to be burned, while still allowing croptop posts.
contract CroptopProjectOwner is IERC721Receiver {
    /// @notice The contract where operator permissions are stored.
    IJBPermissions immutable public PERMISSIONS;

    /// @notice The contract from which project are minted.
    IJBProjects immutable public PROJECTS;

    /// @notice The Croptop publisher.
    CroptopPublisher immutable public PUBLISHER;

    /// @param _operatorStore The contract where operator permissions are stored.
    constructor(IJBPermissions permissions, IJBProjects projects, CroptopPublisher publisher) {
        PERMISSIONS = permissions;
        PROJECTS = projects;
        PUBLISHER = publisher;
    }

    /// @notice Give the croptop publisher permission to post to the project on this contract's behalf.
    /// @dev Make sure to first configure certain posts before sending this contract ownership.
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    )
        external
        returns (bytes4)
    {
        data;
        from;
        operator;

        // Make sure the 721 received is the JBProjects contract.
        if (msg.sender != address(PROJECTS)) revert();

        // Set the correct permission.
        uint256[] memory permissionIds = new uint256[](1);
        permissionIds[0] = JB721PermissionIds.ADJUST_TIERS;

        // Give the croptop contract permission to post on this contract's behalf.
        PERMISSIONS.setPermissionsFor({
            account: address(this),
            permissionsData: JBPermissionsData({operator: address(publisher), projectId: tokenId, permissionIds: permissionIds})

        });

        return IERC721Receiver.onERC721Received.selector;
    }
}
