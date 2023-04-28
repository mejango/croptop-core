// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721Delegate.sol";

/** 
  @notice
  Criteria for allowed posts.

  @member category A category that should allow posts.
  @member price The minimum price that a post to the specified category should cost.
*/
struct AllowedPost {
    uint256 category;
    uint256 minimumPrice;
}

/** 
  @notice
  A post to be published.

  @member encodedIPFSUri The encoded IPFS URI of the post that is being published.
  @member quantity The quantity of NFTs that should be made available, including the 1 that will be minted alongside this transaction.
  @member price The price being paid for buying the post that is being published.
  @member category The category that the post should be published in.
*/
struct Post {
    bytes32 encodedIPFSUri;
    uint40 quantity;
    uint88 price;
    uint16 category;
}

/** 
  @notice
  A contract that facilitates the distribution of NFT posts to a Juicebox project.
*/
contract CroptopPublisher is Ownable {
    error INCOMPATIBLE_DATA_SOURCE();
    error INSUFFICIENT_AMOUNT();
    error INVALID_FEE_PERCENT();
    error UNAUTHORIZED();
    error UNAUTHORIZED_CATEGORY();

    /** 
      @notice
      The divisor that describes the fee that should be taken. 

      @dev
      This is equal to 100 divided by the fee percent.  
    */
    uint256 public feeDivisor = 20;

    /** 
      @notice
      The controller that directs the projects being posted to. 
    */
    IJBController3_1 public controller;

    /** 
      @notice
      A flag indicating if a category allows posts for each project. 

      _projectId The ID of the project.
      _category The category.
    */
    mapping(uint256 => mapping(uint256 => bool)) public allowedCategoryFor;

    /** 
      @notice
      The minimum accepted price for each post on each category.

      _projectId The ID of the project.
      _category The category.
    */
    mapping(uint256 => mapping(uint256 => uint256)) public minPostPriceFor;

    /** 
      @notice
      The ID of the project to which fees will be routed. 
    */
    uint256 public feeProjectId;

    /** 
      @param _controller The controller that directs the projects being posted to. 
      @param _feeProjectId The ID of the project to which fees will be routed. 
      @param _owner The owner of this contract, who can set the fee.
    */
    constructor(
        IJBController3_1 _controller,
        uint256 _feeProjectId,
        address _owner
    ) {
        controller = _controller;
        feeProjectId = _feeProjectId;
        _transferOwnership(_owner);
    }

    /** 
      @notice
      Publish an NFT to become mintable, and mint a first copy.

      @dev
      A fee is taken into the appropriate treasury.

      @param _projectId The ID of the project to which the NFT should be added.
      @param _posts An array of posts that should be published as NFTs to the specified project.
      @param _beneficiary The beneficiary of the NFT mints and of the fee project's token. 
    */
    function mint(
        uint256 _projectId,
        Post[] memory _posts,
        address _beneficiary
    ) external payable {
        // Get the projects current data source from its current funding cyce's metadata.
        (, JBFundingCycleMetadata memory metadata) = controller
            .currentFundingCycleOf(_projectId);

        // Check to make sure the project's current data source is a IJBTiered721Delegate.
        if (
            !IERC165(metadata.dataSource).supportsInterface(
                type(IJBTiered721Delegate).interfaceId
            )
        ) revert INCOMPATIBLE_DATA_SOURCE();

        // The tier ID that will be created, and the first one that should be minted from, is one more than the current max.
        uint256 _startingTierId = IJBTiered721Delegate(metadata.dataSource)
            .store()
            .maxTierIdOf(metadata.dataSource) + 1;

        // Keep a reference to the number of posts being published.
        uint256 _numberOfPosts = _posts.length;

        // Keep a reference to the tier data that will be created to represent the posts.
        JB721TierParams[] memory _tierDataToAdd = new JB721TierParams[](
            _numberOfPosts
        );

        // Keep a reference to the tier IDs of the posts that should be minted once published.
        uint256[] memory _tierIdsToMint = new uint256[](_numberOfPosts);

        // Keep a reference to the post being iterated on.
        Post memory _post;

        // Keep a reference to the total price being paid.
        uint256 _totalPrice;

        // For each post, create tiers after validating to make sure they fulfill the allowance specified by the project's owner.
        for (uint256 _i; _i < _numberOfPosts; ) {
            // Get the current post being iterated on.
            _post = _posts[_i];

            // Make sure the category being posted to allows publishing.
            if (!allowedCategoryFor[_projectId][_post.category])
                revert UNAUTHORIZED_CATEGORY();

            // Make sure the price being paid for the post is at least the allowed minimum price.
            if (_post.price < minPostPriceFor[_projectId][_post.category])
                revert INSUFFICIENT_AMOUNT();

            // Increment the total price.
            _totalPrice += _post.price;

            // Set the tier.
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

            // Set the ID of the tier to mint.
            _tierIdsToMint[_i] = _startingTierId + _i;

            unchecked {
                ++_i;
            }
        }

        // Make sure the amount sent to this function is at least the specified price of the tier plus the fee.
        if (_totalPrice + (_totalPrice / feeDivisor) < msg.value)
            revert INSUFFICIENT_AMOUNT();

        // Add the new tiers.
        IJBTiered721Delegate(metadata.dataSource).adjustTiers(
            _tierDataToAdd,
            new uint256[](0)
        );

        // Scoped section to prevent stack too deep.
        {
            // Get a reference to the project's current ETH payment terminal.
            IJBPaymentTerminal _projectTerminal = controller
                .directory()
                .primaryTerminalOf(_projectId, JBTokens.ETH);

            // Create the metadata for the payment to specify the tier IDs that should be minted.
            bytes memory _mintMetadata = abi.encode(
                bytes32(feeProjectId), // Referral project ID.
                bytes32(0),
                type(IJB721Delegate).interfaceId,
                false, // Don't allow overspending.
                _tierIdsToMint
            );

            // Make the payment.
            _projectTerminal.pay{value: _totalPrice}(
                _projectId,
                _totalPrice,
                JBTokens.ETH,
                _beneficiary,
                0,
                false,
                "Minted from Croptop",
                _mintMetadata
            );
        }

        // Get a reference to the fee project's current ETH payment terminal.
        IJBPaymentTerminal _feeTerminal = controller
            .directory()
            .primaryTerminalOf(feeProjectId, JBTokens.ETH);

        // Referral project ID.
        bytes memory _feeMetadata = abi.encode(bytes32(feeProjectId));

        // Make the fee payment.
        _feeTerminal.pay{value: address(this).balance}(
            feeProjectId,
            address(this).balance,
            JBTokens.ETH,
            _beneficiary,
            0,
            false,
            "",
            _feeMetadata
        );
    }

    /** 
      @notice
      Project owners can set the allowed criteria for publishing a new NFT to their project.

      @param _projectId The ID of the project having its publishing allowances set.
      @param _allowedPosts An array of criteria for allowed posts.
    */
    function configure(
        uint256 _projectId,
        AllowedPost[] memory _allowedPosts
    ) external {
        // Make sure the caller is the owner of the project.
        if (msg.sender != controller.projects().ownerOf(_projectId))
            revert UNAUTHORIZED();

        // Keep a reference to the number of post criteria.
        uint256 _numberOfAllowedPosts = _allowedPosts.length;

        // Keep a reference to the post criteria being iterated on.
        AllowedPost memory _allowedPost;

        // For each post criteria, save the specifications.
        for (uint256 _i; _i < _numberOfAllowedPosts; ) {
            // Set the post criteria being iterated on.
            _allowedPost = _allowedPosts[_i];

            // Allow posting to the specified category.
            allowedCategoryFor[_projectId][_allowedPost.category] = true;

            // Set the minimum price for posts to the specific category.
            minPostPriceFor[_projectId][_allowedPost.category] = _allowedPost
                .minimumPrice;

            unchecked {
                ++_i;
            }
        }
    }

    /** 
      @notice
      Allow this contract's owner to change the publishing fee.

      @dev
      The max fee is %5.

      @param _percent The percent fee to charge.
    */
    function changeFee(uint256 _percent) external onlyOwner {
        // Make sure the fee is not greater than 5%.
        if (_percent > 5) revert INVALID_FEE_PERCENT();

        // Set the fee divisor.
        feeDivisor = 100 / _percent;
    }
}
