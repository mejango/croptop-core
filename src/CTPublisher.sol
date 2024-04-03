// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core/src/libraries/JBMetadataResolver.sol";
import {JBRulesetMetadata} from "@bananapus/core/src/structs/JBRulesetMetadata.sol";
import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {JB721Tier} from "@bananapus/721-hook/src/structs/JB721Tier.sol";
import {JB721TierConfig} from "@bananapus/721-hook/src/structs/JB721TierConfig.sol";
import {JBOwnable} from "@bananapus/ownable/src/JBOwnable.sol";

import {CTAllowedPost} from "./structs/CTAllowedPost.sol";
import {CTPost} from "./structs/CTPost.sol";

/// @notice A contract that facilitates the permissioned publishing of NFT posts to a Juicebox project.
contract CTPublisher is JBPermissioned, ERC2771Context {
    error TOTAL_SUPPY_MUST_BE_POSITIVE();
    error EMPTY_ENCODED_IPFS_URI(bytes32 encodedUri);
    error INCOMPATIBLE_PROJECT(uint256 projectId, address dataSource, bytes4 expectedInterfaceId);
    error INSUFFICIENT_ETH_SENT(uint256 expected, uint256 sent);
    error NOT_IN_ALLOW_LIST(address[] allowedAddresses);
    error MAX_TOTAL_SUPPLY_LESS_THAN_MIN();
    error HOOK_NOT_PROVIDED();
    error PRICE_TOO_SMALL(uint256 minimumPrice);
    error TOTAL_SUPPLY_TOO_SMALL(uint256 minimumTotalSupply);
    error TOTAL_SUPPLY_TOO_BIG(uint256 maximumTotalSupply);
    error UNAUTHORIZED_TO_POST_IN_CATEGORY();

    event ConfigurePostingCriteria(uint256 indexed projectId, CTAllowedPost[] allowedPosts, address caller);

    event Mint(
        uint256 indexed projectId,
        address indexed nftBeneficiary,
        address indexed feeBeneficiary,
        CTPost[] posts,
        uint256 fee,
        address caller
    );

    /// @notice Packed values that determine the allowance of posts.
    /// @custom:param projectId The ID of the project.
    /// @custom:param nft The NFT contract for which this allowance applies.
    /// @custom:param category The category for which the allowance applies
    mapping(uint256 projectId => mapping(address nft => mapping(uint256 category => uint256))) internal
        _packedAllowanceFor;

    /// @notice Stores addresses that are allowed to post onto an NFT category.
    /// @custom:param projectId The ID of the project.
    /// @custom:param nft The NFT contract for which this allowance applies.
    /// @custom:param category The category for which the allowance applies.
    /// @custom:param address The address to check an allowance for.
    mapping(uint256 projectId => mapping(address nft => mapping(uint256 category => address[]))) internal
        _allowedAddresses;

    /// @notice The ID of the tier that an IPFS metadata has been saved to.
    /// @custom:param projectId The ID of the project.
    /// @custom:param encodedIPFSUri The IPFS URI.
    mapping(uint256 projectId => mapping(bytes32 encodedIPFSUri => uint256)) public tierIdForEncodedIPFSUriOf;

    /// @notice The divisor that describes the fee that should be taken.
    /// @dev This is equal to 100 divided by the fee percent.
    uint256 public constant FEE_DIVISOR = 20;

    /// @notice The controller that directs the projects being posted to.
    IJBController public immutable CONTROLLER;

    /// @notice The ID of the project to which fees will be routed.
    uint256 public immutable FEE_PROJECT_ID;

    /// @notice Get the tiers for the provided encoded IPFS URIs.
    /// @param projectId The ID of the project from which the tiers are being sought.
    /// @param nft The NFT from which to get tiers.
    /// @param encodedIPFSUris The URIs to get tiers of.
    /// @return tiers The tiers that correspond to the provided encoded IPFS URIs. If there's no tier yet, an empty tier
    /// is returned.
    function tiersFor(
        uint256 projectId,
        address nft,
        bytes32[] memory encodedIPFSUris
    )
        external
        view
        returns (JB721Tier[] memory tiers)
    {
        uint256 numberOfEncodedIPFSUris = encodedIPFSUris.length;

        // Initialize the tier array being returned.
        tiers = new JB721Tier[](numberOfEncodedIPFSUris);

        if (nft == address(0)) {
            // Get the projects current data source from its current ruleset's metadata.
            (, JBRulesetMetadata memory metadata) = CONTROLLER.currentRulesetOf(projectId);

            // Set the NFT as the data hook.
            nft = metadata.dataHook;
        }

        // Get the tier for each provided encoded IPFS URI.
        for (uint256 i; i < numberOfEncodedIPFSUris; i++) {
            // Check if there's a tier ID stored for the encoded IPFS URI.
            uint256 tierId = tierIdForEncodedIPFSUriOf[projectId][encodedIPFSUris[i]];

            // If there's a tier ID stored, resolve it.
            if (tierId != 0) {
                tiers[i] = IJB721TiersHook(nft).STORE().tierOf(nft, tierId, false);
            }
        }
    }

    /// @notice Post allowances for a particular category on a particular NFT.
    /// @param projectId The ID of the project.
    /// @param nft The NFT contract for which this allowance applies.
    /// @param category The category for which this allowance applies.
    /// @return minimumPrice The minimum price that a poster must pay to record a new NFT.
    /// @return minimumTotalSupply The minimum total number of available tokens that a minter must set to record a new
    /// NFT.
    /// @return maximumTotalSupply The max total supply of NFTs that can be made available when minting. Leave as 0 for
    /// max.
    /// @return allowedAddresses The addresses allowed to post. Returns empty if all addresses are allowed.
    function allowanceFor(
        uint256 projectId,
        address nft,
        uint256 category
    )
        public
        view
        returns (
            uint256 minimumPrice,
            uint256 minimumTotalSupply,
            uint256 maximumTotalSupply,
            address[] memory allowedAddresses
        )
    {
        if (nft == address(0)) {
            // Get the projects current data source from its current funding cyce's metadata.
            (, JBRulesetMetadata memory metadata) = CONTROLLER.currentRulesetOf(projectId);

            // Set the NFT as the data hook.
            nft = metadata.dataHook;
        }

        // Get a reference to the packed values.
        uint256 packed = _packedAllowanceFor[projectId][nft][category];

        // minimum price in bits 0-103 (104 bits).
        minimumPrice = uint256(uint104(packed));
        // minimum supply in bits 104-135 (32 bits).
        minimumTotalSupply = uint256(uint32(packed >> 104));
        // minimum supply in bits 136-67 (32 bits).
        maximumTotalSupply = uint256(uint32(packed >> 136));

        allowedAddresses = _allowedAddresses[projectId][nft][category];
    }

    /// @param controller The controller that directs the projects being posted to.
    /// @param permissions A contract storing permissions.
    /// @param feeProjectId The ID of the project to which fees will be routed.
    /// @param trustedForwarder The trusted forwarder for the ERC2771Context.
    constructor(
        IJBController controller,
        IJBPermissions permissions,
        uint256 feeProjectId,
        address trustedForwarder
    )
        JBPermissioned(permissions)
        ERC2771Context(trustedForwarder)
    {
        CONTROLLER = controller;
        FEE_PROJECT_ID = feeProjectId;
    }

    /// @notice Publish an NFT to become mintable, and mint a first copy.
    /// @dev A fee is taken into the appropriate treasury.
    /// @param projectId The ID of the project to which the NFT should be added.
    /// @param posts An array of posts that should be published as NFTs to the specified project.
    /// @param nftBeneficiary The beneficiary of the NFT mints.
    /// @param feeBeneficiary The beneficiary of the fee project's token.
    /// @param additionalPayMetadata Metadata bytes that should be included in the pay function's metadata. This
    /// prepends the
    /// payload needed for NFT creation.
    /// @param feeMetadata The metadata to send alongside the fee payment.
    function mintFrom(
        uint256 projectId,
        CTPost[] memory posts,
        address nftBeneficiary,
        address feeBeneficiary,
        bytes calldata additionalPayMetadata,
        bytes calldata feeMetadata
    )
        external
        payable
    {
        // Keep a reference a reference to the fee.
        uint256 fee;

        // Keep a reference to the mint metadata.
        bytes memory mintMetadata;

        {
            // Get the projects current data source from its current funding cyce's metadata.
            (, JBRulesetMetadata memory metadata) = CONTROLLER.currentRulesetOf(projectId);

            // Check to make sure the project's current data source is a IJBTiered721Delegate.
            if (!IERC165(metadata.dataHook).supportsInterface(type(IJB721TiersHook).interfaceId)) {
                revert INCOMPATIBLE_PROJECT(projectId, metadata.dataHook, type(IJB721TiersHook).interfaceId);
            }

            // Setup the posts.
            (JB721TierConfig[] memory tiersToAdd, uint256[] memory tierIdsToMint, uint256 totalPrice) =
                _setupPosts(projectId, metadata.dataHook, posts);

            // Keep a reference to the fee that will be paid.
            fee = projectId == FEE_PROJECT_ID ? 0 : (totalPrice / FEE_DIVISOR);

            // Make sure the amount sent to this function is at least the specified price of the tier plus the fee.
            if (totalPrice + fee < msg.value) {
                revert INSUFFICIENT_ETH_SENT(totalPrice, msg.value);
            }

            // Add the new tiers.
            IJB721TiersHook(metadata.dataHook).adjustTiers(tiersToAdd, new uint256[](0));

            // Create the metadata for the payment to specify the tier IDs that should be minted. We create manually the
            // original metadata, following
            // the specifications from the JBMetadataResolver library.
            mintMetadata = JBMetadataResolver.addToMetadata({
                originalMetadata: additionalPayMetadata,
                idToAdd: bytes4(bytes20(metadata.dataHook)),
                dataToAdd: abi.encode(true, tierIdsToMint)
            });

            // Store the referal id in the first 32 bytes of the metadata (push to stack for immutable in assembly)
            uint256 feeProjectId = FEE_PROJECT_ID;

            assembly {
                mstore(add(mintMetadata, 32), feeProjectId)
            }
        }

        {
            // Get a reference to the project's current ETH payment terminal.
            IJBTerminal projectTerminal = CONTROLLER.DIRECTORY().primaryTerminalOf(projectId, JBConstants.NATIVE_TOKEN);

            // Keep a reference to the amount being paid.
            uint256 payValue = msg.value - fee;

            // Make the payment.
            projectTerminal.pay{value: payValue}({
                projectId: projectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: payValue,
                beneficiary: nftBeneficiary,
                minReturnedTokens: 0,
                memo: "Minted from Croptop",
                metadata: mintMetadata
            });
        }

        // Pay a fee if there are funds left.
        if (address(this).balance != 0) {
            // Get a reference to the fee project's current ETH payment terminal.
            IJBTerminal feeTerminal = CONTROLLER.DIRECTORY().primaryTerminalOf(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

            // Make the fee payment.
            feeTerminal.pay{value: address(this).balance}({
                projectId: FEE_PROJECT_ID,
                amount: address(this).balance,
                token: JBConstants.NATIVE_TOKEN,
                beneficiary: feeBeneficiary,
                minReturnedTokens: 0,
                memo: "",
                metadata: feeMetadata
            });
        }

        emit Mint(projectId, nftBeneficiary, feeBeneficiary, posts, fee, _msgSender());
    }

    /// @notice Collection owners can set the allowed criteria for publishing a new NFT to their project.
    /// @param projectId The ID of the project having its publishing allowances set.
    /// @param allowedPosts An array of criteria for allowed posts.
    function configurePostingCriteriaFor(uint256 projectId, CTAllowedPost[] memory allowedPosts) public {
        // Keep a reference to the number of post criteria.
        uint256 numberOfAllowedPosts = allowedPosts.length;

        // Keep a reference to the post criteria being iterated on.
        CTAllowedPost memory allowedPost;

        // For each post criteria, save the specifications.
        for (uint256 i; i < numberOfAllowedPosts; i++) {
            // Set the post criteria being iterated on.
            allowedPost = allowedPosts[i];

            // Enforce permissions.
            _requirePermissionFrom({
                account: JBOwnable(allowedPost.nft).owner(),
                projectId: projectId,
                permissionId: JBPermissionIds.ADJUST_721_TIERS
            });

            // Make sure there is a minimum supply.
            if (allowedPost.minimumTotalSupply == 0) {
                revert TOTAL_SUPPY_MUST_BE_POSITIVE();
            }

            // Make sure there is a minimum supply.
            if (allowedPost.minimumTotalSupply > allowedPost.maximumTotalSupply) {
                revert MAX_TOTAL_SUPPLY_LESS_THAN_MIN();
            }

            uint256 packed;
            // minimum price in bits 0-103 (104 bits).
            packed |= uint256(allowedPost.minimumPrice);
            // minimum total supply in bits 104-135 (32 bits).
            packed |= uint256(allowedPost.minimumTotalSupply) << 104;
            // maximum total supply in bits 136-167 (32 bits).
            packed |= uint256(allowedPost.maximumTotalSupply) << 136;
            // Store the packed value.
            _packedAllowanceFor[projectId][allowedPost.nft][allowedPost.category] = packed;

            // Store the allow list.
            uint256 numberOfAddresses = allowedPost.allowedAddresses.length;
            // Reset the addresses.
            delete _allowedAddresses[projectId][allowedPost.nft][allowedPost.category];
            // Add the number allowed addresses.
            if (numberOfAddresses != 0) {
                // Keep a reference to the storage of the allowed addresses.
                for (uint256 j = 0; j < numberOfAddresses; j++) {
                    _allowedAddresses[projectId][allowedPost.nft][allowedPost.category].push(
                        allowedPost.allowedAddresses[j]
                    );
                }
            }
        }

        emit ConfigurePostingCriteria(projectId, allowedPosts, _msgSender());
    }

    /// @notice Setup the posts.
    /// @param projectId The ID of the project having posts set up.
    /// @param nft The NFT address on which the posts will apply.
    /// @param posts An array of posts that should be published as NFTs to the specified project.
    /// @return tiersToAdd The tiers that will be created to represent the posts.
    /// @return tierIdsToMint The tier IDs of the posts that should be minted once published.
    /// @return totalPrice The total price being paid.
    function _setupPosts(
        uint256 projectId,
        address nft,
        CTPost[] memory posts
    )
        internal
        returns (JB721TierConfig[] memory tiersToAdd, uint256[] memory tierIdsToMint, uint256 totalPrice)
    {
        // Keep a reference to the number of posts being published.
        uint256 numberOfMints = posts.length;

        // Set the max size of the tier data that will be added.
        tiersToAdd = new JB721TierConfig[](numberOfMints);

        // Set the size of the tier IDs of the posts that should be minted once published.
        tierIdsToMint = new uint256[](numberOfMints);

        // The tier ID that will be created, and the first one that should be minted from, is one more than the current
        // max.
        uint256 startingTierId = IJB721TiersHook(nft).STORE().maxTierIdOf(nft) + 1;

        // Keep a reference to the post being iterated on.
        CTPost memory post;

        // Keep a reference to the total number of tiers being added.
        uint256 numberOfTiersBeingAdded;

        // For each post, create tiers after validating to make sure they fulfill the allowance specified by the
        // project's owner.
        for (uint256 i; i < numberOfMints; i++) {
            // Get the current post being iterated on.
            post = posts[i];

            // Make sure the post includes an encodedIPFSUri.
            if (post.encodedIPFSUri == bytes32("")) {
                revert EMPTY_ENCODED_IPFS_URI(post.encodedIPFSUri);
            }

            // Scoped section to prevent stack too deep.
            {
                // Check if there's an ID of a tier already minted for this encodedIPFSUri.
                uint256 tierId = tierIdForEncodedIPFSUriOf[projectId][post.encodedIPFSUri];

                if (tierId != 0) tierIdsToMint[i] = tierId;
            }

            // If no tier already exists, post the tier.
            if (tierIdsToMint[i] == 0) {
                // Scoped error handling section to prevent Stack Too Deep.
                {
                    // Get references to the allowance.
                    (
                        uint256 minimumPrice,
                        uint256 minimumTotalSupply,
                        uint256 maximumTotalSupply,
                        address[] memory addresses
                    ) = allowanceFor(projectId, nft, post.category);

                    // Make sure the category being posted to allows publishing.
                    if (minimumTotalSupply == 0) {
                        revert UNAUTHORIZED_TO_POST_IN_CATEGORY();
                    }

                    // Make sure the price being paid for the post is at least the allowed minimum price.
                    if (post.price < minimumPrice) {
                        revert PRICE_TOO_SMALL(minimumPrice);
                    }

                    // Make sure the total supply being made available for the post is at least the allowed minimum
                    // total supply.
                    if (post.totalSupply < minimumTotalSupply) {
                        revert TOTAL_SUPPLY_TOO_SMALL(minimumTotalSupply);
                    }

                    // Make sure the total supply being made available for the post is at most the allowed maximum total
                    // supply.
                    if (post.totalSupply > maximumTotalSupply) {
                        revert TOTAL_SUPPLY_TOO_BIG(maximumTotalSupply);
                    }

                    // Make sure the address is allowed to post.
                    if (addresses.length != 0 && !_isAllowed(_msgSender(), addresses)) {
                        revert NOT_IN_ALLOW_LIST(addresses);
                    }
                }

                // Set the tier.
                tiersToAdd[numberOfTiersBeingAdded] = JB721TierConfig({
                    price: uint80(post.price),
                    initialSupply: post.totalSupply,
                    votingUnits: 0,
                    reserveFrequency: 0,
                    reserveBeneficiary: address(0),
                    encodedIPFSUri: post.encodedIPFSUri,
                    category: uint8(post.category),
                    allowOwnerMint: false,
                    useReserveBeneficiaryAsDefault: false,
                    transfersPausable: false,
                    useVotingUnits: true,
                    cannotBeRemoved: false
                });

                // Set the ID of the tier to mint.
                tierIdsToMint[i] = startingTierId + numberOfTiersBeingAdded++;

                // Save the encodedIPFSUri as minted.
                tierIdForEncodedIPFSUriOf[projectId][post.encodedIPFSUri] = tierIdsToMint[i];
            }

            // Increment the total price.
            totalPrice += post.price;
        }

        // Resize the array if there's a mismatch in length.
        if (numberOfTiersBeingAdded != numberOfMints) {
            assembly ("memory-safe") {
                mstore(tiersToAdd, numberOfTiersBeingAdded)
            }
        }
    }

    /// @notice Check if an address is included in an allow list.
    /// @param addrs The candidate address.
    /// @param addresses An array of allowed addresses.
    function _isAllowed(address addrs, address[] memory addresses) internal pure returns (bool) {
        uint256 numberOfAddresses = addresses.length;
        for (uint256 i; i < numberOfAddresses; i++) {
            if (addrs == addresses[i]) return true;
        }
        return false;
    }

    /// @notice Returns the sender, prefered to use over `msg.sender`
    /// @return sender the sender address of this call.
    function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    /// @notice Returns the calldata, prefered to use over `msg.data`
    /// @return calldata the `msg.data` of this call
    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @dev ERC-2771 specifies the context as being a single address (20 bytes).
    function _contextSuffixLength() internal view virtual override(ERC2771Context, Context) returns (uint256) {
        return super._contextSuffixLength();
    }
}
