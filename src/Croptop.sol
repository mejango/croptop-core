// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBProjects.sol";

contract Croptop {
    error UNAUTHORIZED();

    IJBController3_1 public controller;
    mapping(uint256 => uint16) public categoryForProject;
    uint256 public feeProjectId;

    constructor(IJBController3_1 _controller, uint256 _feeProjectId) {
        controller = _controller;
        feeProjectId = _feeProjectId;
    }

    function mint(
        uint256 _projectId,
        bytes32[] memory _encodedIPFSUris,
        address _benenficiary
    ) external payable {
        // Get the projects current data source.
        (, JBFundingCycleMetadata memory metadata) = controller
            .currentFundingCyclesOf(_projectId);

        // Check to make sure the data source is a IJBTiered721Delegate;
        if (
            !IERC165(metadata.dataSource).supportsInterface(
                type(IJBTiered721Delegate).interfaceId
            )
        ) revert INCOMPATIBLE_DATA_SOURCE();

        uint256 _startingTierId = IJBTiered721Delegate(metadata.dataSource)
            .store()
            .maxTierIdOf(metadata.dataSource);

        uint256 _numberOfTiers = _encodedIPFSUris.length;

        JB721TierParams[] memory _tierDataToAdd = new JB721TierParams[](
            _numberOfTiers
        );

        uint16[] memory _tierIdsToMint = new uint16[](_encodedIPFSUris.length);

        uint256 _fee = msg.value / 10;
        uint256 _unitPrice = (msg.value - _fee) / _numberOfTiers;

        for (uint256 _i; _i < _numberOfTiers; ) {
            _tierDataToAdd[_i] = JB721TierParams({
                price: _unitPrice,
                initialQuantity: 1,
                votingUnits: 0,
                reservedRate: 0,
                reservedTokenBeneficiary: address(0),
                royaltyRate: 0,
                royaltyBeneficiary: address(0),
                encodedIPFSUri: _encodedIPFSUris[_i],
                category: categoryForProject[_projectId],
                allowManualMint: false,
                shouldUseReservedTokenBeneficiaryAsDefault: false,
                shouldUseRoyaltyBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false
            });
            _tierIdsToMint[_i] = _startingTierId + _i + 1;
            unchecked {
                ++_i;
            }
        }

        IJBTiered721Delegate(metadata.dataSource).adjustTiers(
            _tierDataToAdd,
            new uint256[](0)
        );

        IJBPaymentTerminal _projectTerminal = controller
            .directory()
            .primaryTerminalOf(_projectId, JBTokens.ETH);

        bytes memory _mintMetadata = abi.encode(
            bytes32(feeProjectId),
            bytes32(0),
            type(IJB721Delegate).interfaceId,
            false,
            _tierIdsToMint
        );

        _projectTerminal.pay{value: _unitPrice * _numberOfTiers}(
            _projectId,
            _unitPrice * _numberOfTiers,
            JBTokens.ETH,
            _benenficiary,
            0,
            false,
            "Minted from Croptop",
            _mintMetadata
        );

        IJBPaymentTerminal _feeTerminal = controller
            .directory()
            .primaryTerminalOf(_feeProjectId, JBTokens.ETH);

        bytes memory _feeMetadata = abi.encode(bytes32(feeProjectId));

        _feeTerminal.pay{value: _fee}(
            feeProjectId,
            _fee,
            JBTokens.ETH,
            _benenficiary,
            0,
            false,
            "",
            _feeMetadata
        );
    }

    function configure(uint256 _projectId) external {
        if (msg.sender != controller.projects().ownerOf(_projectId))
            revert UNAUTHORIZED();
    }
}
