// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "cowprotocol/libraries/GPv2Order.sol";
import "cowprotocol/libraries/GPv2Interaction.sol";
import "cowprotocol/GPv2Settlement.sol";

/**
 * @title TemporalCoW - A contract that allows for flashloan settlement
 * @author Cow Protocol Developers + mfw78
 * @notice TBD
 */
contract TemporalCow is ReentrancyGuard {
    // --- variables
    GPv2Authentication public immutable authenticator;
    GPv2Settlement public immutable settlement;

    GPv2Interaction.Data public callback;

    /**
     * Initialise the temporal CoW contract with the main settlement contract.
     * @param _settlement the main settlement contract
     */
    constructor(GPv2Settlement _settlement) {
        settlement = _settlement;
        authenticator = GPv2Authentication(address(_settlement.authenticator()));
    }

    // --- modifiers

    /// @dev This modifier is called by settle function to block any non-listed
    /// senders from settling batches.
    modifier onlySolver() {
        require(authenticator.isSolver(msg.sender), "GPv2: not a solver");
        _;
    }


    function callWhileExpectingCallback(GPv2Interaction.Data call, GPv2Interaction.Data _callback)
        external
        onlySolver
    {
        // `callback` is a settlement for us, `call` is what we want to do that triggers
        // any kind of callback to this contract (leading to fallback handler being invoked)
        callback = _callback;
        GPv2Interaction.execute(call);
        require(!callback);
    }

    fallback() external nonReentrant {
        require(callback);
        GPv2Interaction.execute(callback);
        delete callback;
    }


}
