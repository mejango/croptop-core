// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { IJBController3_1 } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import { IJBOperatable } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatable.sol";
import { IJBTiered721DelegateProjectDeployer } from
    "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateProjectDeployer.sol";
import { IJBTiered721DelegateStore } from
    "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateStore.sol";
import { CroptopPublisher } from "../src/CroptopPublisher.sol";
import { CroptopDeployer } from "../src/CroptopDeployer.sol";
import { CroptopProjectOwner } from "../src/CroptopProjectOwner.sol";

contract DeployMainnet is Script {
    function setUp() public { }

    function _run() internal {
        vm.broadcast();
    }
}

contract DeployGoerli is Script {
    // V3_1 goerli controller.
    IJBController3_1 _controller = IJBController3_1(0x1d260DE91233e650F136Bf35f8A4ea1F2b68aDB6);
    IJBTiered721DelegateProjectDeployer _deployer =
        IJBTiered721DelegateProjectDeployer(0xFf2FC0238d17e4B7892fca999b6865A112Ee1539);
    IJBTiered721DelegateStore _store = IJBTiered721DelegateStore(0x8dA6B4569f88C0164d77Af5E5BF12E88d4bCd016);
    uint256 _feeProjectId = 1016;

    function run() external {
        vm.startBroadcast();

        // Deploy the deployer.
        CroptopPublisher _publisher = new CroptopPublisher(_controller, _feeProjectId);
        new CroptopDeployer(_controller, _deployer, _store, _publisher);
        new CroptopProjectOwner(IJBOperatable(address(_controller)).operatorStore(), _controller.projects(), _publisher);
    }
}
