// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {JBMetadataResolver} from "lib/juice-contracts-v4/src/libraries/JBMetadataResolver.sol";

/// @notice Quick test to assert the creation of metadata while minting
/// @dev    This test is not meant to be exhaustive, but to ensure that the metadata is valid.
///         It uses a mock contract which only returns a metadata following the logic
///         of the CroptopPublisher contract during mint.
contract Test_MetadataGeneration_Unit is Test {

    MockPublisher _mockPublisher;

    function setUp() public {
        _mockPublisher = new MockPublisher();
    }
    
    /// @notice Create a new metadata from the _additionalPayMetadata and the datahook metadata (containing the tiers to mint).
    /// @dev    Naming follows CroptopPublisher contract.
    function test_metadataBuilding() public {       
        // The id's we expect to find in the new metadata:
        uint256 FEE_PROJECT_ID = 420;
        bytes4 datahookId = bytes4(bytes20(address(_mockPublisher)));

        // The data which was added to the metadata:
        bytes memory _additionalPayMetadata = abi.encodePacked(bytes32(hex'1234567890'), bytes32(hex'deadbeef'));
        uint256[] memory tierIdsToMint = new uint256[](9);

        for (uint256 i = 0; i < 9; i++) {
            tierIdsToMint[i] = i + 1;
        }

        // Test: create the new metadata:
        bytes memory _returnedMetadata = _mockPublisher.mintFrom(FEE_PROJECT_ID, _additionalPayMetadata);

        // Check: both data are present and correct?
        (bool found, bytes memory targetData) = JBMetadataResolver.getDataFor(bytes4(uint32(FEE_PROJECT_ID)), _returnedMetadata);
        assertTrue(found, "_additionalPayMetadata not found");
        assertEq(targetData, _additionalPayMetadata, "_additionalPayMetadata not equal");

        (found, targetData) = JBMetadataResolver.getDataFor(datahookId, _returnedMetadata);
        assertTrue(found, "datahook metadata not found");
        assertEq(targetData, abi.encode(true, tierIdsToMint), "datahook not equal");
    }

}

/// @notice Mock contract to return a metadata following the logic of the CroptopPublisher contract during mint.
contract MockPublisher {
    function mintFrom(
        uint256 _feeProjectId,
        bytes calldata additionalPayMetadata
    )
        external
        payable
        returns (bytes memory)
    {   
        // mock data (same naming as CroptopPublisher contract)
        address dataHook = address(this);
        uint256[] memory tierIdsToMint = new uint256[](9);

        for (uint256 i = 0; i < 9; i++) {
            tierIdsToMint[i] = i + 1;
        }

        // Recreate the metadata, as ln244 of CroptopPublisher contract:
        bytes memory mintMetadata = JBMetadataResolver.addToMetadata({
            originalMetadata: abi.encodePacked(bytes32(0), bytes32(abi.encodePacked(uint32(_feeProjectId), uint8(2))), additionalPayMetadata),
            idToAdd: bytes4(bytes20(dataHook)),
            dataToAdd: abi.encode(true, tierIdsToMint)
        });

        return mintMetadata;
    }
}