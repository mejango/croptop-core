// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721Delegate.sol";

struct AllowedPost {
    uint256 category;
    uint256 price;
}

struct Post {
    bytes32 encodedIPFSUri;
    uint40 quantity;
    uint88 price;
    uint16 category;
}

contract Croptop is Ownable {
    error INCOMPATIBLE_DATA_SOURCE();
    error INSUFFICIENT_AMOUNT();
    error INVALID_FEE_PERCENT();
    error UNAUTHORIZED();
    error UNAUTHORIZED_CATEGORY();

    uint256 public feeDivisor = 20;
    IJBController3_1 public controller;
    mapping(uint256 => mapping(uint256 => bool)) public allowedCategoryFor;
    mapping(uint256 => mapping(uint256 => uint256)) public minPostPriceFor;
    uint256 public feeProjectId;

    constructor(
        IJBController3_1 _controller,
        uint256 _feeProjectId,
        address _owner
    ) {
        controller = _controller;
        feeProjectId = _feeProjectId;
        _transferOwnership(_owner);
    }

    function mint(
        uint256 _projectId,
        Post[] memory _posts,
        address _benenficiary
    ) external payable {
        // Get the projects current data source.
        (, JBFundingCycleMetadata memory metadata) = controller
            .currentFundingCycleOf(_projectId);

        // Check to make sure the project's current data source is a IJBTiered721Delegate;
        if (
            !IERC165(metadata.dataSource).supportsInterface(
                type(IJBTiered721Delegate).interfaceId
            )
        ) revert INCOMPATIBLE_DATA_SOURCE();

        // The tier ID that will be created, and the first one that should be minted from, is one more than the current max.
        uint256 _startingTierId = IJBTiered721Delegate(metadata.dataSource)
            .store()
            .maxTierIdOf(metadata.dataSource) + 1;

        uint256 _numberOfPosts = _posts.length;

        JB721TierParams[] memory _tierDataToAdd = new JB721TierParams[](
            _numberOfPosts
        );

        uint256[] memory _tierIdsToMint = new uint256[](_numberOfPosts);

        Post memory _post;
        uint256 _totalPrice;

        for (uint256 _i; _i < _numberOfPosts; ) {
            _post = _posts[_i];
            if (!allowedCategoryFor[_projectId][_post.category])
                revert UNAUTHORIZED_CATEGORY();
            if (_post.price < minPostPriceFor[_projectId][_post.category])
                revert INSUFFICIENT_AMOUNT();
            _totalPrice += _post.price;
            _tierDataToAdd[_i] = JB721TierParams({
                price: _post.price,
                initialQuantity: _post.quantity,
                votingUnits: 0,
                reservedRate: 0,
                reservedTokenBeneficiary: address(0),
                royaltyRate: 0,
                royaltyBeneficiary: address(0),
                encodedIPFSUri: _post.encodedIPFSUri,
                category: _post.category,
                allowManualMint: false,
                shouldUseReservedTokenBeneficiaryAsDefault: false,
                shouldUseRoyaltyBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false
            });
            _tierIdsToMint[_i] = _startingTierId + _i;
            unchecked {
                ++_i;
            }
        }

        if (_totalPrice + (_totalPrice / feeDivisor) < msg.value)
            revert INSUFFICIENT_AMOUNT();

        IJBTiered721Delegate(metadata.dataSource).adjustTiers(
            _tierDataToAdd,
            new uint256[](0)
        );

        {
            IJBPaymentTerminal _projectTerminal = controller
                .directory()
                .primaryTerminalOf(_projectId, JBTokens.ETH);

            bytes memory _mintMetadata = abi.encode(
                bytes32(feeProjectId), // Referral project ID.
                bytes32(0),
                type(IJB721Delegate).interfaceId,
                false, // Don't allow overspending.
                _tierIdsToMint
            );

            _projectTerminal.pay{value: _totalPrice}(
                _projectId,
                _totalPrice,
                JBTokens.ETH,
                _benenficiary,
                0,
                false,
                "Minted from Croptop",
                _mintMetadata
            );
        }

        IJBPaymentTerminal _feeTerminal = controller
            .directory()
            .primaryTerminalOf(feeProjectId, JBTokens.ETH);

        // Referral project ID.
        bytes memory _feeMetadata = abi.encode(bytes32(feeProjectId));

        _feeTerminal.pay{value: address(this).balance}(
            feeProjectId,
            address(this).balance,
            JBTokens.ETH,
            _benenficiary,
            0,
            false,
            "",
            _feeMetadata
        );
    }

    function configure(
        uint256 _projectId,
        AllowedPost[] memory _allowedPosts
    ) external {
        if (msg.sender != controller.projects().ownerOf(_projectId))
            revert UNAUTHORIZED();

        uint256 _numberOfAllowedPosts = _allowedPosts.length;
        AllowedPost memory _allowedPost;

        for (uint256 _i; _i < _numberOfAllowedPosts; ) {
            _allowedPost = _allowedPosts[_i];
            allowedCategoryFor[_projectId][_allowedPost.category] = true;
            minPostPriceFor[_projectId][_allowedPost.category] = _allowedPost
                .price;
            unchecked {
                ++_i;
            }
        }
    }

    function changeFee(uint256 _percent) external onlyOwner {
        if (_percent > 5) revert INVALID_FEE_PERCENT();
        feeDivisor = 100 / _percent;
    }
}
