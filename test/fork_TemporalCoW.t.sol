// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";

import {ChainlogHelper} from "dss-interfaces/dss/ChainlogAbstract.sol";
import {FlashAbstract} from "dss-interfaces/dss/FlashAbstract.sol";
import {DssCdpManagerAbstract} from "dss-interfaces/dss/DssCdpManager.sol";
import {SafeProxyFactory} from "safe/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "safe/proxies/SafeProxy.sol";
import {Safe} from "safe/Safe.sol";

import "../src/TemporalCoW.sol";

import {GPv2AllowListAuthentication} from "cowprotocol/GPv2AllowListAuthentication.sol";

contract ForkTemporalCoWTest is Test, ChainlogHelper {
    TemporalCow temporalCow;
    address solver = address(0x123);
    GPv2Settlement settlement;
    FlashAbstract flash;
    DssCdpManagerAbstract cdpManager;
    Safe safe;
    uint256 cdp;

    address usr = address(0x456);

    // immutable variables
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function setUp() public {
        settlement = GPv2Settlement(payable(vm.envAddress("SETTLEMENT")));
        flash = FlashAbstract(vm.envAddress("MCD_FLASH"));
        cdpManager = DssCdpManagerAbstract(vm.envAddress("MCD_CDP_MANAGER"));

        // --- safe
        SafeProxyFactory factory = SafeProxyFactory(vm.envAddress("SAFE_PROXY_FACTORY"));

        address[] memory owners = new address[](1);
        owners[0] = usr;

        SafeProxy proxy = factory.createProxyWithNonce(
            0xc962E67D9490E154D81181879ddf4CD3b65D2132,
            abi.encodeCall(
                Safe.setup,
                (
                    owners,
                    1,
                    address(0),
                    "",
                    address(0),
                    address(0),
                    0,
                    payable(address(0))
                )
            ),
            123
        );
        safe = Safe(payable(address(proxy)));

        // dish out some DAI and ETH
        deal(address(DAI), usr, 10000000000000 ether);
        deal(address(WETH), usr, 1000 ether);

        // --- temporal cow

        // setup the temporal cow
        temporalCow = new TemporalCow(settlement, flash);

        // authorise a solver
        GPv2AllowListAuthentication auth = GPv2AllowListAuthentication(vm.envAddress("ALLOW_LIST"));
        // 1. Get the manager's address
        address manager = auth.manager();
        vm.startPrank(manager);
        // 2. Authorise the solver
        auth.addSolver(solver);
        auth.addSolver(address(temporalCow));
        vm.stopPrank();

        // --- create a cdp
        vm.startPrank(address(safe));
        cdp = cdpManager.open("ETH-A", address(safe)); // -- cdp
        // DAI.approve(address(DAI_JOIN), type(uint256).max);
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

    function testTemporalCow_flashloanAndSettle_CanBeCalledBySolver() public {
        vm.prank(solver);

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

        // Define preSettlementInteractions as an array of size 1 GPv2Interaction.Data
        GPv2Interaction.Data[] memory preSettlementInteractions = new GPv2Interaction.Data[](2);
        preSettlementInteractions[0] = GPv2Interaction.Data({
            target: address(DAI),
            value: 0,
            callData: abi.encodeCall(IERC20.approve, (address(flash), type(uint256).max))
        });
        preSettlementInteractions[1] = GPv2Interaction.Data({
            target: address(flash),
            value: 0,
            callData: abi.encodeCall(FlashAbstract.flashLoan, (address(temporalCow), address(DAI), 500000000000000000000000000, "")) // TODO: fill in
        });

        temporalCow.flashloanAndSettle(preSettlementInteractions, settlementInteraction);

        // Ensure that the callback is no longer set
        testTemporalCow_RevertIfCallbackNotSet();
    }

    function testTemporalCow_settle_CanBeCalledBySolver() public {
        vm.prank(solver);

        IERC20[] memory tokens = new IERC20[](0);
        uint256[] memory clearingPrices = new uint256[](0);
        GPv2Trade.Data[] memory trades = new GPv2Trade.Data[](0);
        GPv2Interaction.Data[][3] memory interactions =
            [new GPv2Interaction.Data[](0), new GPv2Interaction.Data[](0), new GPv2Interaction.Data[](0)];
        
        // straight up call the settle function which actually auto-wraps with a flashloan
        temporalCow.settle(tokens, clearingPrices, trades, interactions);
    }
}
