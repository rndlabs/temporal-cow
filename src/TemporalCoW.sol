// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "cowprotocol/libraries/GPv2Order.sol";
import "cowprotocol/libraries/GPv2Interaction.sol";
import "cowprotocol/GPv2Settlement.sol";

/**
 * @title TemporalCoW - A contract that allows for flashloan settlement
 * @author CoW Protocol Developers + mfw78
 * @notice TBD
 */
contract TemporalCow is ReentrancyGuard {
    // --- immutable variables
    GPv2Authentication public immutable authenticator;
    GPv2Settlement public immutable settlement;

    // --- mutable variables
    GPv2Interaction.Data private callback;   // use TSTORE in the future

    // --- errors
    error NotSolver();
    error NoCallback();
    error CallbackNotCleared();

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
        if (!authenticator.isSolver(msg.sender)) {
            revert(NotSolver());
        }
        _;
    }

    /**
     * Execute interactions prior to the main settlement
     * @param call interactions to be executed prior to callback
     * @param _callback interaction to be executed as the callback
     */
    function flashloanAndSettle(GPv2Interaction.Data[] calldata calls, GPv2Interaction.Data _callback)
        external
        onlySolver
    {
        // `callback` is a settlement for us, `call` is what we want to do that triggers
        // any kind of callback to this contract (leading to fallback handler being invoked)

        // *TODO*: Do we want to enforce that the `callback` is indeed to the settlement contract?
        //      If so, we can do it by checking the `target` of the `callback` interaction.

        // We set the `callback` to be `_callback`, as we do NOT want to trust the flashloan
        // contract or any of the calldata provided by it. The maximum that would be at risk is
        // equal to balances held by the settlement contract.
        callback = _callback;
        for (uint256 i = 0; i < calls.length; i++) {
            GPv2Interaction.Data calldata call = calls[i];
            GPv2Interaction.execute(call);
        }
        if (callback) {
            revert(CallbackNotCleared());
        }
    }

    /**
     * Fallback handler to generalise ERC-3156 / AAVE flashloan callback.
     * @dev By using a fallback handler here we can cover any flashloan callback.
     */
    fallback() external nonReentrant {
        if (!callback) {
            // If there is no callback, we revert.
            revert(NoCallback());
        }
        GPv2Interaction.execute(callback);
        delete callback;
    }
}