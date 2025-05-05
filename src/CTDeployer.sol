// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBPermissioned} from "@bananapus/core/src/interfaces/IJBPermissioned.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers/src/interfaces/IJBSuckerRegistry.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core/src/structs/JBBeforePayRecordedContext.sol";
import {JBCashOutHookSpecification} from "@bananapus/core/src/structs/JBCashOutHookSpecification.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBBeforeCashOutRecordedContext} from "@bananapus/core/src/structs/JBBeforeCashOutRecordedContext.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

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
import {JBCurrencyIds} from "@bananapus/core/src/libraries/JBCurrencyIds.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

import {ICTDeployer} from "./interfaces/ICTDeployer.sol";
import {ICTPublisher} from "./interfaces/ICTPublisher.sol";
import {CTAllowedPost} from "./structs/CTAllowedPost.sol";
import {CTDeployerAllowedPost} from "./structs/CTDeployerAllowedPost.sol";

/// @notice A contract that facilitates deploying a simple Juicebox project to receive posts from Croptop templates.
contract CTDeployer is ERC2771Context, JBPermissioned, IJBRulesetDataHook, IERC721Receiver, ICTDeployer {
    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice The controller that projects are made from.
    IJBController public immutable override CONTROLLER;

    /// @notice The deployer to launch Croptop recorded collections from.
    IJB721TiersHookProjectDeployer public immutable override DEPLOYER;

    /// @notice The Croptop publisher.
    ICTPublisher public immutable override PUBLISHER;

     /// @notice Deploys and tracks suckers for projects.
    IJBSuckerRegistry public immutable SUCKER_REGISTRY;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice Each project's data hook provided on deployment.
    /// @custom:param projectId The ID of the project to get the data hook for.
    /// @custom:param rulesetId The ID of the ruleset to get the data hook for.
    mapping(uint256 projectId => IJBRulesetDataHook) public dataHookOf;

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
        JBPermissioned(IJBPermissioned(address(controller)).PERMISSIONS())
    {
        CONTROLLER = controller;
        DEPLOYER = deployer;
        PUBLISHER = publisher;
    }

     //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Forward the call to the original data hook.
    /// @dev This function is part of `IJBRulesetDataHook`, and gets called before the revnet processes a payment.
    /// @param context Standard Juicebox payment context. See `JBBeforePayRecordedContext`.
    /// @return weight The weight which project tokens are minted relative to. This can be used to customize how many
    /// tokens get minted by a payment.
    /// @return hookSpecifications Amounts (out of what's being paid in) to be sent to pay hooks instead of being paid
    /// into the project. Useful for automatically routing funds from a treasury as payments come in.
    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        external
        view
        override
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        // Otherwise, forward the call to the datahook.
        return dataHookOf[context.projectId].beforePayRecordedWith(context);
    }

    /// @notice Allow cash outs from suckers without a tax.
    /// @dev This function is part of `IJBRulesetDataHook`, and gets called before the revnet processes a cash out.
    /// @param context Standard Juicebox cash out context. See `JBBeforeCashOutRecordedContext`.
    /// @return cashOutTaxRate The cash out tax rate, which influences the amount of terminal tokens which get cashed
    /// out.
    /// @return cashOutCount The number of project tokens that are cashed out.
    /// @return totalSupply The total project token supply.
    /// @return hookSpecifications The amount of funds and the data to send to cash out hooks (this contract).
    function beforeCashOutRecordedWith(JBBeforeCashOutRecordedContext calldata context)
        external
        view
        override
        returns (
            uint256 cashOutTaxRate,
            uint256 cashOutCount,
            uint256 totalSupply,
            JBCashOutHookSpecification[] memory hookSpecifications
        )
    {
        // If the cash out is from a sucker, return the full cash out amount without taxes or fees.
        if (SUCKER_REGISTRY.isSuckerOf(context.projectId, context.holder)) {
            return (0, context.cashOutCount, context.totalSupply, hookSpecifications);
        }

        // If the ruleset has a data hook, forward the call to the datahook.
        return dataHookOf[context.projectId].beforeCashOutRecordedWith(context);
    }

    /// @notice A flag indicating whether an address has permission to mint a project's tokens on-demand.
    /// @dev A project's data hook can allow any address to mint its tokens.
    /// @param projectId The ID of the project whose token can be minted.
    /// @param addr The address to check the token minting permission of.
    /// @return flag A flag indicating whether the address has permission to mint the project's tokens on-demand.
    function hasMintPermissionFor(uint256 projectId, address addr) external view returns (bool flag) {
        // If the address is a sucker for this project.
        return SUCKER_REGISTRY.isSuckerOf(projectId, addr);
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

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See `IERC165.supportsInterface`.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ICTDeployer).interfaceId
            || interfaceId == type(IJBRulesetDataHook).interfaceId || interfaceId == type(IERC721Receiver).interfaceId;
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

        // Set the data hook for the project.
        dataHookOf[projectId] = IJBRulesetDataHook(hook);

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

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /// @notice The calldata. Preferred to use over `msg.data`.
    /// @return calldata The `msg.data` of this call.
    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @notice The message's sender. Preferred to use over `msg.sender`.
    /// @return sender The address which sent this call.
    function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    /// @dev ERC-2771 specifies the context as being a single address (20 bytes).
    function _contextSuffixLength() internal view virtual override(ERC2771Context, Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }
}
