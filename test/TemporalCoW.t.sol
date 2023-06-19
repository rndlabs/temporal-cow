// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";

import {ChainlogHelper} from "dss-interfaces/dss/ChainlogAbstract.sol";
import {BaseComposableCoWTest} from "composable/test/ComposableCoW.base.t.sol";

import "../src/TemporalCoW.sol";

contract TemporalCoWTest is BaseComposableCoWTest, ChainlogHelper {
    TemporalCow temporalCow;

    function setUp() public override {
        super.setUp();
        temporalCow = new TemporalCow(settlement);
    }

    function testTemporalCow_RevertIfNotASolver() public {
        vm.expectRevert(TemporalCow.NotSolver.selector);
        temporalCow.flashloanAndSettle(new GPv2Interaction.Data[](0), GPv2Interaction.Data(address(0), 0, ""));
    }

    function testTemporalCow_RevertIfCallbackNotSet() public {
        bytes memory cd = abi.encodeWithSignature("testtest()");
        (bool success, bytes memory returnData) = address(temporalCow).call(cd);
        assertEq(success, false);
        assertEq(bytes4(returnData), TemporalCow.NoCallback.selector);
    }

    function testTemporalCow_CanBeCalledBySolver() public {
        vm.prank(solver.addr);

        IERC20[] memory tokens = new IERC20[](0);
        uint256[] memory clearingPrices = new uint256[](0);
        GPv2Trade.Data[] memory trades = new GPv2Trade.Data[](0);
        GPv2Interaction.Data[][3] memory interactions =
            [new GPv2Interaction.Data[](0), new GPv2Interaction.Data[](0), new GPv2Interaction.Data[](0)];

        // second define the settlement interaction (this will be set as the callback)
        GPv2Interaction.Data memory settlementInteraction = GPv2Interaction.Data({
            target: address(settlement),
            value: 0,
            callData: abi.encodeCall(GPv2Settlement.settle, (tokens, clearingPrices, trades, interactions))
        });

        temporalCow.flashloanAndSettle(new GPv2Interaction.Data[](0), settlementInteraction);

        // Ensure that the callback is no longer set
        testTemporalCow_RevertIfCallbackNotSet();
    }

    function testTemporalCoW() public {
        assertEq(true, true);
    }
}
