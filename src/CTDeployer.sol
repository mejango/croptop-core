// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookProjectDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookProjectDeployer.sol";
import {IJB721TokenUriResolver} from "@bananapus/721-hook/src/interfaces/IJB721TokenUriResolver.sol";
import {JB721InitTiersConfig} from "@bananapus/721-hook/src/structs/JB721InitTiersConfig.sol";
import {JB721TierConfig} from "@bananapus/721-hook/src/structs/JB721TierConfig.sol";
import {JB721TiersHookFlags} from "@bananapus/721-hook/src/structs/JB721TiersHookFlags.sol";
import {JBDeploy721TiersHookConfig} from "@bananapus/721-hook/src/structs/JBDeploy721TiersHookConfig.sol";
import {JBLaunchProjectConfig} from "@bananapus/721-hook/src/structs/JBLaunchProjectConfig.sol";
import {JBPayDataHookRulesetConfig} from "@bananapus/721-hook/src/structs/JBPayDataHookRulesetConfig.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBPrices} from "@bananapus/core/src/interfaces/IJBPrices.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

import {ICTDeployer} from "./interfaces/ICTDeployer.sol";
import {ICTPublisher} from "./interfaces/ICTPublisher.sol";
import {CTAllowedPost} from "./structs/CTAllowedPost.sol";
import {CTDeployerAllowedPost} from "./structs/CTDeployerAllowedPost.sol";

/// @notice A contract that facilitates deploying a simple Juicebox project to receive posts from Croptop templates.
contract CTDeployer is ERC2771Context, IERC721Receiver, ICTDeployer {
    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice The controller that projects are made from.
    IJBController public immutable override CONTROLLER;

    /// @notice The deployer to launch Croptop recorded collections from.
    IJB721TiersHookProjectDeployer public immutable override DEPLOYER;

    /// @notice The Croptop publisher.
    ICTPublisher public immutable override PUBLISHER;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param controller The controller that projects are made from.
    /// @param deployer The deployer to launch Croptop projects from.
    /// @param publisher The croptop publisher.
    constructor(
        IJBController controller,
        IJB721TiersHookProjectDeployer deployer,
        ICTPublisher publisher,
        address trusted_forwarder
    )
        ERC2771Context(trusted_forwarder)
    {
        CONTROLLER = controller;
        DEPLOYER = deployer;
        PUBLISHER = publisher;
    }

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @dev Make sure only mints can be received.
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    )
        external
        view
        returns (bytes4)
    {
        data;
        tokenId;
        operator;

        // Make sure the 721 received is the JBProjects contract.
        if (msg.sender != address(CONTROLLER.PROJECTS())) revert();
        // Make sure the 721 is being received as a mint.
        if (from != address(0)) revert();
        return IERC721Receiver.onERC721Received.selector;
    }
    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Deploy a simple project meant to receive posts from Croptop templates.
    /// @param owner The address that'll own the project.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param projectUri The metadata URI containing project info.
    /// @param allowedPosts The type of posts that the project should allow.
    /// @param contractUri A link to the collection's metadata.
    /// @param name The name of the collection where posts will go.
    /// @param symbol The symbol of the collection where posts will go.
    /// @param salt A salt to use for the deterministic deployment.
    /// @return projectId The ID of the newly created project.
    /// @return hook The hook that was created.
    function deployProjectFor(
        address owner,
        JBTerminalConfig[] memory terminalConfigurations,
        string memory projectUri,
        CTDeployerAllowedPost[] memory allowedPosts,
        string memory contractUri,
        string memory name,
        string memory symbol,
        bytes32 salt
    )
        external
        returns (uint256 projectId, IJB721TiersHook hook)
    {
        JBPayDataHookRulesetConfig[] memory rulesetConfigurations = new JBPayDataHookRulesetConfig[](1);
        rulesetConfigurations[0].weight = 1_000_000 * (10 ** 18);
        rulesetConfigurations[0].metadata.baseCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));

        // Deploy a blank project.
        (projectId, hook) = DEPLOYER.launchProjectFor({
            owner: address(this),
            deployTiersHookConfig: JBDeploy721TiersHookConfig({
                name: name,
                symbol: symbol,
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: contractUri,
                tiersConfig: JB721InitTiersConfig({
                    tiers: new JB721TierConfig[](0),
                    currency: JBCurrencyIds.ETH,
                    decimals: 18,
                    prices: CONTROLLER.PRICES()
                }),
                reserveBeneficiary: address(0),
                flags: JB721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            launchProjectConfig: JBLaunchProjectConfig({
                projectUri: projectUri,
                rulesetConfigurations: rulesetConfigurations,
                terminalConfigurations: terminalConfigurations,
                memo: "Deployed from Croptop"
            }),
            controller: CONTROLLER,
            salt: keccak256(abi.encode(salt, _msgSender()))
        });

        // Configure allowed posts.
        if (allowedPosts.length > 0) _configurePostingCriteriaFor(address(hook), allowedPosts);

        //transfer to _owner.
        CONTROLLER.PROJECTS().transferFrom(address(this), owner, projectId);
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Configure croptop posting.
    /// @param hook The hook that will be posted to.
    /// @param allowedPosts The type of posts that should be allowed.
    function _configurePostingCriteriaFor(address hook, CTDeployerAllowedPost[] memory allowedPosts) internal {
        // Keep a reference to the number of allowed posts.
        uint256 numberOfAllowedPosts = allowedPosts.length;

        // Keep a reference to the formatted allowed posts.
        CTAllowedPost[] memory formattedAllowedPosts = new CTAllowedPost[](numberOfAllowedPosts);

        // Keep a reference to the post being iterated on.
        CTDeployerAllowedPost memory post;

        // Iterate through each post to add it to the formatted list.
        for (uint256 i; i < numberOfAllowedPosts; i++) {
            // Set the post being iterated on.
            post = allowedPosts[i];

            // Set the formatted post.
            formattedAllowedPosts[i] = CTAllowedPost({
                hook: hook,
                category: post.category,
                minimumPrice: post.minimumPrice,
                minimumTotalSupply: post.minimumTotalSupply,
                maximumTotalSupply: post.maximumTotalSupply,
                allowedAddresses: post.allowedAddresses
            });
        }

        // Set up the allowed posts in the publisher.
        PUBLISHER.configurePostingCriteriaFor({allowedPosts: formattedAllowedPosts});
    }
}
