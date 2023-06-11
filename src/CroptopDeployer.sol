// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBCurrencies.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateProjectDeployer.sol";
import "@jbx-protocol/juice-721-delegate/contracts/enums/JB721GovernanceType.sol";
import "@jbx-protocol/juice-721-delegate/contracts/structs/JBTiered721FundingCycleMetadata.sol";
import "@jbx-protocol/juice-721-delegate/contracts/libraries/JBTiered721FundingCycleMetadataResolver.sol";
import "./CroptopPublisher.sol";

/// @notice A contract that facilitates deploying a simple Juicebox project to receive posts from Croptop templates.
contract CroptopDeployer is IERC721Receiver {
    /// @notice The controller that projects are made from.
    IJBController3_1 public controller;

    /// @notice The deployer to launch Croptop recorded collections from.
    IJBTiered721DelegateProjectDeployer public deployer;

    /// @notice The contract storing NFT data for newly deployed collections.
    IJBTiered721DelegateStore public store;

    /// @notice The Croptop publisher.
    CroptopPublisher public publisher;

    /// @param _controller The controller that projects are made from.
    /// @param _deployer The deployer to launch Croptop projects from.
    /// @param _store The contract storing NFT data for newly deployed collections.
    /// @param _publisher The croptop publisher.
    constructor(
        IJBController3_1 _controller,
        IJBTiered721DelegateProjectDeployer _deployer,
        IJBTiered721DelegateStore _store,
        CroptopPublisher _publisher
    ) {
        controller = _controller;
        deployer = _deployer;
        store = _store;
        publisher = _publisher;
    }

    /// @notice Deploy a simple project meant to receive posts from Croptop templates.
    /// @param _owner The address that'll own the project.
    /// @param _terminal The contract that the project will begin receiving funds from.
    /// @param _projectMetadata The metadata containing project info.
    /// @param _allowedPosts The type of posts that the project should allow.
    /// @param _contractUri A link to the collection's metadata.
    /// @param _name The name of the collection where posts will go.
    /// @param _symbol The symbol of the collection where posts will go.
    /// @return projectId The ID of the newly created project.
    function deployProjectFor(
        address _owner,
        IJBPaymentTerminal _terminal,
        JBProjectMetadata calldata _projectMetadata,
        AllowedPost[] calldata _allowedPosts,
        string calldata _contractUri,
        string memory _name,
        string memory _symbol
    ) external returns (uint256 projectId) {
        // Initialize the terminal array .
        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1);
        _terminals[0] = _terminal;

        // Deploy a blank project.
        projectId = deployer.launchProjectFor({
            _owner: address(this),
            _deployTieredNFTRewardDelegateData: JBDeployTiered721DelegateData({
                name: _name,
                symbol: _symbol,
                fundingCycleStore: controller.fundingCycleStore(),
                baseUri: "ipfs://",
                tokenUriResolver: IJBTokenUriResolver(address(0)),
                contractUri: _contractUri,
                owner: _owner,
                pricing: JB721PricingParams({
                    tiers: new JB721TierParams[](0),
                    currency: uint48(JBCurrencies.ETH),
                    decimals: 18,
                    prices: IJBPrices(address(0))
                }),
                reservedTokenBeneficiary: address(0),
                store: store,
                flags: JBTiered721Flags({
                    lockReservedTokenChanges: false,
                    lockVotingUnitChanges: false,
                    lockManualMintingChanges: false,
                    preventOverspending: false
                }),
                governanceType: JB721GovernanceType.NONE
            }),
            _launchProjectData: JBLaunchProjectData({
                projectMetadata: _projectMetadata,
                data: JBFundingCycleData({
                    duration: 0,
                    weight: 1000000000000000000000000,
                    discountRate: 0,
                    ballot: IJBFundingCycleBallot(address(0))
                }),
                metadata: JBPayDataSourceFundingCycleMetadata({
                    global: JBGlobalFundingCycleMetadata({
                        allowSetTerminals: false,
                        allowSetController: false,
                        pauseTransfers: false
                    }),
                    reservedRate: 0,
                    redemptionRate: 0,
                    ballotRedemptionRate: 0,
                    pausePay: false,
                    pauseDistributions: false,
                    pauseRedeem: false,
                    pauseBurn: false,
                    allowMinting: false,
                    allowTerminalMigration: false,
                    allowControllerMigration: false,
                    holdFees: false,
                    preferClaimedTokenOverride: false,
                    useTotalOverflowForRedemptions: false,
                    useDataSourceForRedeem: false,
                    metadata: JBTiered721FundingCycleMetadataResolver.packFundingCycleGlobalMetadata(
                        JBTiered721FundingCycleMetadata({pauseTransfers: false, pauseMintingReserves: false})
                        )
                }),
                mustStartAtOrAfter: 0,
                groupedSplits: new JBGroupedSplits[](0),
                fundAccessConstraints: new JBFundAccessConstraints[](0),
                terminals: _terminals,
                memo: "Deployed from Croptop"
            }),
            _controller: controller
        });

        // Configure allowed posts.
        if (_allowedPosts.length > 0) publisher.configureFor(projectId, _allowedPosts);

        //transfer to _owner.
        controller.projects().transferFrom(address(this), _owner, projectId);
    }

    // Need to implement this to own a Juicebox project.
    function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes calldata _data)
        view
        external
        returns (bytes4)
    {
        _data;
        _tokenId;
        _operator;

        // Make sure the 721 received is the JBProjects contract.
        if (msg.sender != address(controller.projects())) revert();
        // Make sure the 721 is being received as a mint.
        if (_from != address(0)) revert();
        return IERC721Receiver.onERC721Received.selector;
    }
}
