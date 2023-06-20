// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FlashAbstract} from "dss-interfaces/dss/FlashAbstract.sol";

import "cowprotocol/libraries/GPv2Order.sol";
import "cowprotocol/libraries/GPv2Interaction.sol";
import "cowprotocol/mixins/ReentrancyGuard.sol";
import "cowprotocol/GPv2Settlement.sol";

/**
 * @title TemporalCoW - A contract that allows for flashloan settlement
 * @author CoW Protocol Developers + mfw78
 * @notice TBD
 */
contract TemporalCow is ReentrancyGuard {
    // --- constants
    IERC20 private constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    // --- immutable variables
    GPv2Authentication public immutable authenticator;
    GPv2Settlement public immutable settlement;
    FlashAbstract public immutable flash;

    // --- mutable variables
    GPv2Interaction.Data private callback; // use TSTORE in the future

    // --- errors
    error NotSolver();
    error NoCallback();
    error CallbackNotCleared();

    /**
     * Initialise the temporal CoW contract with the main settlement contract.
     * @param _settlement the main settlement contract
     */
    constructor(GPv2Settlement _settlement, FlashAbstract _flash) {
        settlement = _settlement;
        flash = _flash;
        authenticator = GPv2Authentication(address(_settlement.authenticator()));

        // On initialization we need to approve the flashloan contract to pull DAI
        dai.approve(address(_flash), type(uint256).max);
    }

    // --- modifiers

    /// @dev This modifier is called by settle function to block any non-listed
    /// senders from settling batches.
    modifier onlySolver() {
        if (!authenticator.isSolver(msg.sender)) {
            revert NotSolver();
        }
        _;
    }

    /**
     * A hacky workaround to minimize work in the backend.
     * @dev See GPv2Settlement.settle
     */
    function settle(
        IERC20[] calldata,
        uint256[] calldata,
        GPv2Trade.Data[] calldata,
        GPv2Interaction.Data[][3] calldata
    ) external onlySolver {
        callback = GPv2Interaction.Data(address(settlement), 0, msg.data);

        // The flashloan contract is already approved to pull dai, so we can just call it
        flash.flashLoan(address(this), address(dai), flash.max(), "");

        // Clear the callback after the settlement is done, so the fallback handler is protected
        callback = GPv2Interaction.Data(address(0), 0, "");
    }

    /**
     * Execute interactions prior to the main settlement
     * @param calls interactions to be executed prior to callback
     * @param _callback interaction to be executed as the callback
     */
    function flashloanAndSettle(GPv2Interaction.Data[] calldata calls, GPv2Interaction.Data calldata _callback)
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
        // We clear the callback after the settlement is done, so that we can't be re-entered
        // by the settlement contract.
        callback = GPv2Interaction.Data(address(0), 0, "");
    }

    /**
     * Fallback handler to generalise ERC-3156 / AAVE flashloan callback.
     * @dev By using a fallback handler here we can cover any flashloan callback.
     */
    fallback(bytes calldata) external nonReentrant returns (bytes memory) {
        // If the callback is an empty interaction, we revert.
        if (!(callback.target != address(0))) {
            revert NoCallback();
        }

        execute(callback);

        return abi.encode(keccak256("ERC3156FlashBorrower.onFlashLoan"));
    }

    // --- internal helpers

    /// @dev Execute an arbitraty contract interaction from storage.
    /// @param interaction Interaction data.
    function execute(GPv2Interaction.Data memory interaction) internal {
        // call the target with the callData and value
        (bool success, ) = interaction.target.call{value: interaction.value}(interaction.callData);

        // revert if the call failed
        require(success);
    }
}
