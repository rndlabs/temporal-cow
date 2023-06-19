// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";

import {Base} from "composable/test/Base.t.sol";

contract TemporalCoWTest is Base {

    TemporalCoW temporalCow;

    function setUp() public override {
        super.setUp();

        temporalCow = new TemporalCoW(settlement);
    }

    function testTemporalCoW() public {
        assertEq(true, true);
    }
}