// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/721-hook/script/helpers/Hook721DeploymentLib.sol";
import "@bananapus/buyback-hook/script/helpers/BuybackDeploymentLib.sol";
import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";
import "@bananapus/suckers/script/helpers/SuckerDeploymentLib.sol";
import "@bananapus/swap-terminal/script/helpers/SwapTerminalDeploymentLib.sol";
import "@rev-net/core/script/helpers/RevnetCoreDeploymentLib.sol";
import "./helpers/CroptopDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import {IJB721TokenUriResolver} from "@bananapus/721-hook/src/interfaces/IJB721TokenUriResolver.sol";
import {JBDeploy721TiersHookConfig} from "@bananapus/721-hook/src/structs/JBDeploy721TiersHookConfig.sol";
import {JB721InitTiersConfig} from "@bananapus/721-hook/src/structs/JB721InitTiersConfig.sol";
import {JB721TierConfig} from "@bananapus/721-hook/src/structs/JB721TierConfig.sol";
import {JB721TiersHookFlags} from "@bananapus/721-hook/src/structs/JB721TiersHookFlags.sol";
import {IJBPrices} from "@bananapus/core/src/interfaces/IJBPrices.sol";
import {IJBSplitHook} from "@bananapus/core/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBSplit} from "@bananapus/core/src/structs/JBSplit.sol";
import {JBCurrencyIds} from "@bananapus/core/src/libraries/JBCurrencyIds.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers/src/structs/JBSuckerDeployerConfig.sol";
import {JBTokenMapping} from "@bananapus/suckers/src/structs/JBTokenMapping.sol";
import {REVAutoIssuance} from "@rev-net/core/src/structs/REVAutoIssuance.sol";
import {REVBuybackHookConfig} from "@rev-net/core/src/structs/REVBuybackHookConfig.sol";
import {REVBuybackPoolConfig} from "@rev-net/core/src/structs/REVBuybackPoolConfig.sol";
import {REVConfig} from "@rev-net/core/src/structs/REVConfig.sol";
import {REVCroptopAllowedPost} from "@rev-net/core/src/structs/REVCroptopAllowedPost.sol";
import {REVDeploy721TiersHookConfig} from "@rev-net/core/src/structs/REVDeploy721TiersHookConfig.sol";
import {REVDescription} from "@rev-net/core/src/structs/REVDescription.sol";
import {REVLoanSource} from "@rev-net/core/src/structs/REVLoanSource.sol";
import {REVStageConfig} from "@rev-net/core/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core/src/structs/REVSuckerDeploymentConfig.sol";

struct FeeProjectConfig {
    REVConfig configuration;
    JBTerminalConfig[] terminalConfigurations;
    REVBuybackHookConfig buybackHookConfiguration;
    REVSuckerDeploymentConfig suckerDeploymentConfiguration;
    REVDeploy721TiersHookConfig hookConfiguration;
    REVCroptopAllowedPost[] allowedPosts;
}

contract ConfigureFeeProjectScript is Script, Sphinx {
    /// @notice tracks the deployment of the buyback hook.
    BuybackDeployment buybackHook;
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the latest croptop deployment.
    CroptopDeployment croptop;
    /// @notice tracks the deployment of the 721 hook contracts for the chain we are deploying to.
    Hook721Deployment hook;
    /// @notice tracks the deployment of the revnet contracts for the chain we are deploying to.
    RevnetCoreDeployment revnet;
    /// @notice tracks the deployment of the sucker contracts for the chain we are deploying to.
    SuckerDeployment suckers;
    /// @notice tracks the deployment of the swap terminal.
    SwapTerminalDeployment swapTerminal;

    // @notice set this to a non-zero value to re-use an existing projectID. Having it set to 0 will deploy a new
    // fee_project.
    uint256 FEE_PROJECT_ID;

    uint32 PREMINT_CHAIN_ID = 11_155_111;
    string NAME = "Croptop Publishing Network";
    string SYMBOL = "CPN";
    string PROJECT_URI = "ipfs://QmNXa96G26ZHxw5AP8oYcQ9q32Aw4F46sAfzZJ2PYYYFeY";
    uint32 NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));
    uint32 ETH_CURRENCY = JBCurrencyIds.ETH;
    uint8 DECIMALS = 18;
    uint256 DECIMAL_MULTIPLIER = 10 ** DECIMALS;
    bytes32 SUCKER_SALT = "_CPN_SUCKER_";
    bytes32 ERC20_SALT = "_CPN_ERC20_SALT_";
    bytes32 HOOK_SALT = "_CPN_HOOK_SALT_";
    address OPERATOR = 0x823b92d6a4b2AED4b15675c7917c9f922ea8ADAD;
    address TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;
    uint256 TIME_UNTIL_START = 1 days;

    function configureSphinx() public override {
        // TODO: Update to contain croptop devs.
        sphinxConfig.projectName = "croptop-core-testnet";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core/deployments/"))
        );
        // Get the deployment addresses for the croptop contracts for this chain.
        croptop = CroptopDeploymentLib.getDeployment(
            vm.envOr("CROPTOP_DEPLOYMENT_PATH", string("node_modules/@croptop/core/deployments/"))
        );
        // Get the deployment addresses for the 721 hook contracts for this chain.
        hook = Hook721DeploymentLib.getDeployment(
            vm.envOr("NANA_721_DEPLOYMENT_PATH", string("node_modules/@bananapus/721-hook/deployments/"))
        );
        // Get the deployment addresses for the 721 hook contracts for this chain.
        revnet = RevnetCoreDeploymentLib.getDeployment(
            vm.envOr("REVNET_CORE_DEPLOYMENT_PATH", string("node_modules/@rev-net/core/deployments/"))
        );
        // Get the deployment addresses for the suckers contracts for this chain.
        suckers = SuckerDeploymentLib.getDeployment(
            vm.envOr("NANA_SUCKERS_DEPLOYMENT_PATH", string("node_modules/@bananapus/suckers/deployments/"))
        );
        // Get the deployment addresses for the 721 hook contracts for this chain.
        swapTerminal = SwapTerminalDeploymentLib.getDeployment(
            vm.envOr("NANA_SWAP_TERMINAL_DEPLOYMENT_PATH", string("node_modules/@bananapus/swap-terminal/deployments/"))
        );

        // We do a quick sanity check to make sure revnet and croptop use the same juicebox core contracts.
        require(
            revnet.basic_deployer.CONTROLLER() == croptop.publisher.CONTROLLER(),
            "The revnet package artifacts are using a different version of the core contracts than the croptop artifacts."
        );

        // Since Juicebox has logic dependent on the timestamp we warp time to create a scenario closer to production.
        // We force simulations to make the assumption that the `START_TIME` has not occured,
        // and is not the current time.
        // Because of the cross-chain allowing components of nana-core, all chains require the same start_time,
        // for this reason we can't rely on the simulations block.time and we need a shared timestamp across all
        // simulations.
        uint256 realTimestamp = vm.envUint("START_TIME");
        if (realTimestamp <= block.timestamp - TIME_UNTIL_START) {
            revert("Something went wrong while setting the 'START_TIME' environment variable.");
        }

        vm.warp(realTimestamp);

        // Get the fee project id from the croptop deployment.
        FEE_PROJECT_ID = croptop.publisher.FEE_PROJECT_ID();

        // Check if there should be a new fee project created.
        // Perform the deployment transactions.
        deploy();
    }

    function getCroptopRevnetConfig() internal view returns (FeeProjectConfig memory) {
        // The tokens that the project accepts and stores.
        JBAccountingContext[] memory accountingContextsToAccept = new JBAccountingContext[](1);

        // Accept the chain's native currency through the multi terminal.
        accountingContextsToAccept[0] =
            JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: DECIMALS, currency: NATIVE_CURRENCY});

        // The terminals that the project will accept funds through.
        JBTerminalConfig[] memory terminalConfigurations = new JBTerminalConfig[](2);
        terminalConfigurations[0] =
            JBTerminalConfig({terminal: core.terminal, accountingContextsToAccept: accountingContextsToAccept});
        terminalConfigurations[1] = JBTerminalConfig({
            terminal: IJBTerminal(address(swapTerminal.swap_terminal)),
            accountingContextsToAccept: new JBAccountingContext[](0)
        });

        REVAutoIssuance[] memory issuanceConfs = new REVAutoIssuance[](1);
        issuanceConfs[0] = REVAutoIssuance({
            chainId: PREMINT_CHAIN_ID,
            count: uint104(100_000 * DECIMAL_MULTIPLIER),
            beneficiary: OPERATOR
        });

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(OPERATOR),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        // The project's revnet stage configurations.
        REVStageConfig[] memory stageConfigurations = new REVStageConfig[](3);
        stageConfigurations[0] = REVStageConfig({
            autoIssuances: issuanceConfs,
            startsAtOrAfter: uint40(block.timestamp + TIME_UNTIL_START),
            splitPercent: 3800, // 38%
            splits: splits,
            initialIssuance: uint112(1000 * DECIMAL_MULTIPLIER),
            issuanceCutFrequency: 90 days,
            issuanceCutPercent: 380_000_000, // 38%
            cashOutTaxRate: 2000, // 0.2
            extraMetadata: 4 // Allow adding suckers.
        });

        stageConfigurations[1] = REVStageConfig({
            startsAtOrAfter: uint40(stageConfigurations[0].startsAtOrAfter + 360 days),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 3800, // 38%
            splits: splits,
            initialIssuance: 1, // inherit from previous cycle.
            issuanceCutFrequency: 180 days,
            issuanceCutPercent: 380_000_000, // 38%
            cashOutTaxRate: 2000, // 0.2
            extraMetadata: 4 // Allow adding suckers.
        });

        stageConfigurations[2] = REVStageConfig({
            startsAtOrAfter: uint40(stageConfigurations[1].startsAtOrAfter + (6000 days)),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 1000, // 10%
            splits: splits,
            initialIssuance: 0, // no more issuance.
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: 1000, // 0.1
            extraMetadata: 4 // Allow adding suckers.
        });

        // The projects loan configuration.
        REVLoanSource[] memory loanSources = new REVLoanSource[](1);
        loanSources[0] = REVLoanSource({token: JBConstants.NATIVE_TOKEN, terminal: core.terminal});

        // The project's revnet configuration
        REVConfig memory revnetConfiguration = REVConfig({
            description: REVDescription(NAME, SYMBOL, PROJECT_URI, ERC20_SALT),
            baseCurrency: ETH_CURRENCY,
            splitOperator: OPERATOR,
            stageConfigurations: stageConfigurations,
            loanSources: loanSources,
            loans: address(revnet.loans)
        });

        REVBuybackHookConfig memory buybackHookConfiguration;
        {
            // The project's buyback hook configuration.
            REVBuybackPoolConfig[] memory buybackPoolConfigurations = new REVBuybackPoolConfig[](1);
            buybackPoolConfigurations[0] = REVBuybackPoolConfig({
                token: JBConstants.NATIVE_TOKEN,
                fee: 10_000,
                twapWindow: 2 days,
                twapSlippageTolerance: 9000
            });
            buybackHookConfiguration =
                REVBuybackHookConfig({hook: buybackHook.hook, poolConfigurations: buybackPoolConfigurations});
        }

        // Organize the instructions for how this project will connect to other chains.
        JBTokenMapping[] memory tokenMappings = new JBTokenMapping[](1);
        tokenMappings[0] = JBTokenMapping({
            localToken: JBConstants.NATIVE_TOKEN,
            remoteToken: JBConstants.NATIVE_TOKEN,
            minGas: 200_000,
            minBridgeAmount: 0.01 ether
        });

        REVSuckerDeploymentConfig memory suckerDeploymentConfiguration;

        {
            JBSuckerDeployerConfig[] memory suckerDeployerConfigurations;
            if (block.chainid == 1 || block.chainid == 11_155_111) {
                suckerDeployerConfigurations = new JBSuckerDeployerConfig[](3);
                // OP
                suckerDeployerConfigurations[0] =
                    JBSuckerDeployerConfig({deployer: suckers.optimismDeployer, mappings: tokenMappings});

                suckerDeployerConfigurations[1] =
                    JBSuckerDeployerConfig({deployer: suckers.baseDeployer, mappings: tokenMappings});

                suckerDeployerConfigurations[2] =
                    JBSuckerDeployerConfig({deployer: suckers.arbitrumDeployer, mappings: tokenMappings});
            } else {
                suckerDeployerConfigurations = new JBSuckerDeployerConfig[](1);
                // L2 -> Mainnet
                suckerDeployerConfigurations[0] = JBSuckerDeployerConfig({
                    deployer: address(suckers.optimismDeployer) != address(0)
                        ? suckers.optimismDeployer
                        : address(suckers.baseDeployer) != address(0) ? suckers.baseDeployer : suckers.arbitrumDeployer,
                    mappings: tokenMappings
                });

                if (address(suckerDeployerConfigurations[0].deployer) == address(0)) {
                    revert("L2 > L1 Sucker is not configured");
                }
            }
            // Specify all sucker deployments.
            suckerDeploymentConfiguration =
                REVSuckerDeploymentConfig({deployerConfigurations: suckerDeployerConfigurations, salt: SUCKER_SALT});
        }

        // The project's allowed croptop posts.
        REVCroptopAllowedPost[] memory allowedPosts = new REVCroptopAllowedPost[](5);
        allowedPosts[0] = REVCroptopAllowedPost({
            category: 0,
            minimumPrice: uint104(10 ** (DECIMALS - 5)),
            minimumTotalSupply: 10_000,
            maximumTotalSupply: 999_999_999,
            allowedAddresses: new address[](0)
        });
        allowedPosts[1] = REVCroptopAllowedPost({
            category: 1,
            minimumPrice: uint104(10 ** (DECIMALS - 3)),
            minimumTotalSupply: 10_000,
            maximumTotalSupply: 999_999_999,
            allowedAddresses: new address[](0)
        });
        allowedPosts[2] = REVCroptopAllowedPost({
            category: 2,
            minimumPrice: uint104(10 ** (DECIMALS - 1)),
            minimumTotalSupply: 100,
            maximumTotalSupply: 999_999_999,
            allowedAddresses: new address[](0)
        });
        allowedPosts[3] = REVCroptopAllowedPost({
            category: 3,
            minimumPrice: uint104(10 ** DECIMALS),
            minimumTotalSupply: 10,
            maximumTotalSupply: 999_999_999,
            allowedAddresses: new address[](0)
        });
        allowedPosts[4] = REVCroptopAllowedPost({
            category: 4,
            minimumPrice: uint104(10 ** (DECIMALS + 2)),
            minimumTotalSupply: 10,
            maximumTotalSupply: 999_999_999,
            allowedAddresses: new address[](0)
        });

        return FeeProjectConfig({
            configuration: revnetConfiguration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration,
            hookConfiguration: REVDeploy721TiersHookConfig({
                baseline721HookConfiguration: JBDeploy721TiersHookConfig({
                    name: NAME,
                    symbol: SYMBOL,
                    baseUri: "ipfs://",
                    tokenUriResolver: IJB721TokenUriResolver(address(0)),
                    contractUri: "",
                    tiersConfig: JB721InitTiersConfig({
                        tiers: new JB721TierConfig[](0),
                        currency: ETH_CURRENCY,
                        decimals: DECIMALS,
                        prices: core.prices
                    }),
                    reserveBeneficiary: address(0),
                    flags: JB721TiersHookFlags({
                        noNewTiersWithReserves: false,
                        noNewTiersWithVotes: true,
                        noNewTiersWithOwnerMinting: true,
                        preventOverspending: false
                    })
                }),
                salt: HOOK_SALT,
                splitOperatorCanAdjustTiers: true,
                splitOperatorCanUpdateMetadata: false,
                splitOperatorCanMint: false,
                splitOperatorCanIncreaseDiscountPercent: false
            }),
            allowedPosts: allowedPosts
        });
    }

    function deploy() public sphinx {
        FeeProjectConfig memory feeProjectConfig = getCroptopRevnetConfig();

        // Approve the basic deployer to configure the project and transfer it.
        core.projects.approve(address(revnet.basic_deployer), FEE_PROJECT_ID);

        // Deploy the NANA fee project.
        revnet.basic_deployer.deployWith721sFor({
            revnetId: FEE_PROJECT_ID,
            configuration: feeProjectConfig.configuration,
            terminalConfigurations: feeProjectConfig.terminalConfigurations,
            buybackHookConfiguration: feeProjectConfig.buybackHookConfiguration,
            suckerDeploymentConfiguration: feeProjectConfig.suckerDeploymentConfiguration,
            tiered721HookConfiguration: feeProjectConfig.hookConfiguration,
            allowedPosts: feeProjectConfig.allowedPosts
        });
    }

    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (address, bool)
    {
        address _deployedTo = vm.computeCreate2Address({
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)),
            // Arachnid/deterministic-deployment-proxy address.
            deployer: address(0x4e59b44847b379578588920cA78FbF26c0B4956C)
        });

        // Return if code is already present at this address.
        return (_deployedTo, address(_deployedTo).code.length != 0);
    }
}
