// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC721Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {IJBController} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {JBConstants} from "lib/juice-contracts-v4/src/libraries/JBConstants.sol";
import {JBTerminalConfig} from "lib/juice-contracts-v4/src/structs/JBTerminalConfig.sol";
import {IJBPrices} from "lib/juice-contracts-v4/src/interfaces/IJBPrices.sol";
import {IJB721TiersHookStore} from "lib/juice-721-hook/src/interfaces/IJB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "lib/juice-721-hook/src/interfaces/IJB721TokenUriResolver.sol";
import {IJB721TiersHookProjectDeployer} from "lib/juice-721-hook/src/interfaces/IJB721TiersHookProjectDeployer.sol";
import {JBLaunchProjectConfig} from "lib/juice-721-hook/src/structs/JBLaunchProjectConfig.sol";
import {JBDeploy721TiersHookConfig} from "lib/juice-721-hook/src/structs/JBDeploy721TiersHookConfig.sol";
import {JB721TierConfig} from "lib/juice-721-hook/src/structs/JB721TierConfig.sol";
import {JBDeploy721TiersHookConfig} from "lib/juice-721-hook/src/structs/JBDeploy721TiersHookConfig.sol";
import {JBPayDataHookRulesetConfig} from "lib/juice-721-hook/src/structs/JBPayDataHookRulesetConfig.sol";
import {JB721InitTiersConfig} from "lib/juice-721-hook/src/structs/JB721InitTiersConfig.sol";
import {JB721TiersHookFlags} from "lib/juice-721-hook/src/structs/JB721TiersHookFlags.sol";
import {CroptopPublisher, AllowedPost} from "./CroptopPublisher.sol";

/// @notice A contract that facilitates deploying a simple Juicebox project to receive posts from Croptop templates.
contract CroptopDeployer is IERC721Receiver {
    /// @notice The controller that projects are made from.
    IJBController public immutable CONTROLLER;

    /// @notice The deployer to launch Croptop recorded collections from.
    IJB721TiersHookProjectDeployer public immutable DEPLOYER;

    /// @notice The contract storing NFT data for newly deployed collections.
    IJB721TiersHookStore public STORE;

    /// @notice The Croptop publisher.
    CroptopPublisher public PUBLISHER;

    /// @param controller The controller that projects are made from.
    /// @param deployer The deployer to launch Croptop projects from.
    /// @param store The contract storing NFT data for newly deployed collections.
    /// @param publisher The croptop publisher.
    constructor(
        IJBController controller,
        IJB721TiersHookProjectDeployer deployer,
        IJB721TiersHookStore store,
        CroptopPublisher publisher
    ) {
        CONTROLLER = controller;
        DEPLOYER = deployer;
        STORE = store;
        PUBLISHER = publisher;
    }

    /// @notice Deploy a simple project meant to receive posts from Croptop templates.
    /// @param owner The address that'll own the project.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param projectUri The metadata URI containing project info.
    /// @param allowedPosts The type of posts that the project should allow.
    /// @param contractUri A link to the collection's metadata.
    /// @param name The name of the collection where posts will go.
    /// @param symbol The symbol of the collection where posts will go.
    /// @return projectId The ID of the newly created project.
    function deployProjectFor(
        address owner,
        JBTerminalConfig[] calldata terminalConfigurations,
        string memory projectUri,
        AllowedPost[] calldata allowedPosts,
        string memory contractUri,
        string memory name,
        string memory symbol
    )
        external
        returns (uint256 projectId)
    {
        JBPayDataHookRulesetConfig[] memory rulesetConfigurations = new JBPayDataHookRulesetConfig[](1);
        rulesetConfigurations[0].weight = 1_000_000 * 10 * 18;
        rulesetConfigurations[0].metadata.baseCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));

        // Deploy a blank project.
        projectId = DEPLOYER.launchProjectFor({
            owner: address(this),
            deployTiersHookConfig: JBDeploy721TiersHookConfig({
                name: name,
                symbol: symbol,
                rulesets: CONTROLLER.RULESETS(),
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: contractUri,
                tiersConfig: JB721InitTiersConfig({
                    tiers: new JB721TierConfig[](0),
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                    decimals: 18,
                    prices: IJBPrices(address(0))
                }),
                reserveBeneficiary: address(0),
                store: STORE,
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
            controller: CONTROLLER
        });

        // Configure allowed posts.
        if (allowedPosts.length > 0) PUBLISHER.configurePostingCriteriaFor(projectId, allowedPosts);

        //transfer to _owner.
        CONTROLLER.PROJECTS().transferFrom(address(this), owner, projectId);
    }

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
}
