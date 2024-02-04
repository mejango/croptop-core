// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {JBMetadataResolver} from "lib/juice-contracts-v4/src/libraries/JBMetadataResolver.sol";

import {MetadataResolverHelper} from "lib/juice-contracts-v4/test/helpers/MetadataResolverHelper.sol";

/// @notice Quick test to assert the creation of metadata while minting
/// @dev    This test is not meant to be exhaustive, but to ensure that the metadata is valid.
///         It uses a mock contract which only returns a metadata following the logic
///         of the CroptopPublisher contract during mint. This external contract is used to recreate the same
contract Test_MetadataGeneration_Unit is Test {
    /// @notice Create a new metadata from the _additionalPayMetadata and the datahook metadata (containing the tiers to
    /// mint).
    /// @dev    Naming follows CroptopPublisher contract.
    function test_metadataBuilding() public {
        MetadataResolverHelper _resolverHelper = new MetadataResolverHelper();

        // The intial metadata passed to the terminal
        bytes4[] memory _ids = new bytes4[](10);
        bytes[] memory _datas = new bytes[](10);

        for (uint256 _i; _i < _ids.length; _i++) {
            _ids[_i] = bytes4(uint32(_i + 1 * 1000));
            _datas[_i] = abi.encode(
                bytes1(uint8(_i + 1)), uint32(69), bytes2(uint16(_i + 69)), bytes32(uint256(type(uint256).max))
            );
        }

        bytes memory _additionalPayMetadata = _resolverHelper.createMetadata(_ids, _datas);

        // The referal to include in the first 32 bytes of the metadata
        uint256 FEE_PROJECT_ID = 420;

        // The additional metadata to include
        bytes4 datahookId = bytes4(bytes20(address(0xdeadbeef)));
        uint256[] memory tierIdsToMint = new uint256[](9);

        for (uint256 i = 0; i < 9; i++) {
            tierIdsToMint[i] = i + 1;
        }

        // Test: create the new metadata:
        bytes memory mintMetadata = JBMetadataResolver.addToMetadata({
            originalMetadata: _additionalPayMetadata,
            idToAdd: datahookId,
            dataToAdd: abi.encode(true, tierIdsToMint)
        });

        // Add the referal id in the first 32 bytes
        assembly {
            mstore(add(mintMetadata, 32), FEE_PROJECT_ID)
        }

        bytes memory targetData;
        bool found;

        // Check: both data are present and correct?
        for (uint256 i = 0; i < _ids.length; i++) {
            (found, targetData) = JBMetadataResolver.getDataFor(_ids[i], mintMetadata);
            assertTrue(found, "metadata not found");
            assertEq(targetData, _datas[i], "metadata not equal");
        }

        (found, targetData) = JBMetadataResolver.getDataFor(datahookId, mintMetadata);
        assertTrue(found, "datahook metadata not found");
        assertEq(targetData, abi.encode(true, tierIdsToMint), "datahook not equal");

        assertEq(uint256(bytes32(mintMetadata)), FEE_PROJECT_ID, "referal id not equal");
    }
}
