// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IJBOperatorStore } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import { IJBProjects } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBProjects.sol";
import { JBOperatorData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import { JB721Operations } from "@jbx-protocol/juice-721-delegate/contracts/libraries/JB721Operations.sol"; 
import { CroptopPublisher } from "./CroptopPublisher.sol";

/// @notice A contract that can be sent a project to be burned, while still allowing croptop posts.
contract CroptopProjectOwner is IERC721Receiver {
    /// @notice The contract where operator permissions are stored.
    IJBOperatorStore public operatorStore;

    /// @notice The contract from which project are minted.
    IJBProjects public projects;

    /// @notice The Croptop publisher.
    CroptopPublisher public publisher;

    /// @param _operatorStore The contract where operator permissions are stored.
    constructor(
        IJBOperatorStore _operatorStore,
        IJBProjects _projects,
        CroptopPublisher _publisher
    ) {
        operatorStore = _operatorStore;
        projects = _projects;
        publisher = _publisher;
    }

    /// @notice Give the croptop publisher permission to post to the project on this contract's behalf.
    /// @dev Make sure to first configure certain posts before sending this contract ownership.
    function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes calldata _data)
        external
        returns (bytes4)
    {
        _data;
        _from;
        _operator;

        // Make sure the 721 received is the JBProjects contract.
        if (msg.sender != address(projects)) revert();

        // Set the correct permission.
        uint256[] memory _permissionIndexes = new uint256[](1);
        _permissionIndexes[0] = JB721Operations.ADJUST_TIERS;

        // Give the croptop contract permission to post on this contract's behalf.
        operatorStore.setOperator(JBOperatorData({
          operator: address(publisher),
          domain: _tokenId,
          permissionIndexes: _permissionIndexes
        })); 

        return IERC721Receiver.onERC721Received.selector;
    }
}
