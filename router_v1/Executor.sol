// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {EthReceiver} from "./utils/EthReceiver.sol";
import {Interaction} from "./base/RouterStructs.sol";
import {IExecutor} from "./interfaces/IExecutor.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IWrappedNativeToken} from "./interfaces/IWrappedNativeToken.sol";
import {SafeERC20} from "./lib/SafeERC20.sol";

/**
 * @title GluexExecutor
 * @notice A contract that executes an array of interactions as specified by the caller.
 * @dev This contract processes a sequence of interactions by invoking the target contract methods with provided call data and values.
 */
contract GluexExecutor is EthReceiver, IExecutor {
    using SafeERC20 for IERC20;

    // Errors
    /**
     * @notice Error emitted when an execution call fails.
     * @param target The target address of the failed call.
     * @param callData The call data sent to the target.
     * @param failureData The data returned from the failed call.
     */
    error FailedExecutionCall(
        address target,
        bytes callData,
        bytes failureData
    );
    error InsufficientBalance();
    error NativeTransferFailed();
    error OnlyGlueTreasury();
    error ZeroAddress();

    // Constants
    uint256 private _RAW_CALL_GAS_LIMIT = 5000;

    // State Variables
    address private immutable _gluexRouter;
    address private immutable _glueTreasury;
    address private immutable _nativeToken;
    address private immutable _wrappedNativeToken;

    /**
     * @notice Constructs the GluexExecutor contract.
     * @param gluexRouter The address of the GluexRouter contract.
     * @param gluexTreasury The address of the GluexTreasury contract.
     * @param nativeToken The address of the native token used by the contract.
     * @param wrappedNativeToken The address of the wrapped native token used by the contract.
     */
    constructor(
        address gluexRouter,
        address gluexTreasury,
        address nativeToken,
        address wrappedNativeToken
    ) {
        // Ensure the address is not zero
        checkZeroAddress(gluexRouter);
        checkZeroAddress(gluexTreasury);

        _gluexRouter = gluexRouter;
        _glueTreasury = gluexTreasury;
        _nativeToken = nativeToken;
        _wrappedNativeToken = wrappedNativeToken;
    }

    /**
     * @dev Modifier to restrict access to treasury-only functions.
     */
    modifier onlyTreasury() {
        checkTreasury();
        _;
    }

    /**
     * @notice Verifies the caller is the Glue treasury.
     * @dev Reverts with `OnlyGlueTreasury` if the caller is not the treasury.
     */
    function checkTreasury() internal view {
        if (msg.sender != _glueTreasury) revert OnlyGlueTreasury();
    }

    /**
     * @notice Verifies the given address is not zero.
     * @param addr The address to verify.
     * @dev Reverts with `ZeroAddress` if the address is zero.
     */
    function checkZeroAddress(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddress();
    }

    /**
     * @notice Executes a series of interactions by making low-level calls to the specified targets.
     * @param interactions An array of `Interaction` structs, each containing the target address,
     *                     call data, and value to be sent with the call.
     * @dev Each interaction is executed sequentially. If any call fails, the function reverts with
     *      detailed information about the failed interaction.
     */
    function executeRoute(
        Interaction[] calldata interactions,
        IERC20 outputToken
    ) external payable {
        // Execute interactions sequentially
        uint256 len = interactions.length;
        IERC20 balanceToken;

        if (address(outputToken) == _nativeToken) {
            balanceToken = IERC20(_wrappedNativeToken);
        } else {
            balanceToken = outputToken;
        }

        uint256 outputBalanceBefore = uniBalanceOf(balanceToken, address(this));

        for (uint256 i; i < len; ) {
            // Perform the interaction via a low-level call
            (bool success, bytes memory response) = interactions[i].target.call{
                value: interactions[i].value
            }(interactions[i].callData);

            // Revert if the call fails
            if (!success) {
                revert FailedExecutionCall(
                    interactions[i].target,
                    interactions[i].callData,
                    response
                );
            }

            unchecked {
                ++i;
            }
        }

        uint256 outputBalanceAfter = uniBalanceOf(balanceToken, address(this));

        uint256 outputAmountWithSlippage = outputBalanceAfter - outputBalanceBefore;

        if (address(outputToken) == _nativeToken) {
            // Apply slippage adjusted unwrapping of native token
            IWrappedNativeToken(_wrappedNativeToken).withdraw(outputAmountWithSlippage);
        }

        // Transfer the output token to the GluexRouter
        if (outputAmountWithSlippage > 0)
            uniTransfer(
                outputToken,
                payable(_gluexRouter),
                outputAmountWithSlippage
            );
    }

    /**
     * @notice Retrieves the balance of a specified token for a given account.
     * @param token The ERC20 token to check.
     * @param account The account address to query the balance for.
     * @return The balance of the token for the account.
     */
    function uniBalanceOf(
        IERC20 token,
        address account
    ) internal view returns (uint256) {
        if (address(token) == _nativeToken) {
            uint256 contractBalance;
            assembly {
                contractBalance := balance(account)
            }
            return contractBalance;
        } else {
            return token.balanceOf(account);
        }
    }

    /**
     * @notice Transfers a specified amount of a token to a given address.
     * @param token The ERC20 token to transfer.
     * @param to The address to transfer the token to.
     * @param amount The amount of the token to transfer.
     * @dev Handles both native token and ERC20 transfers.
     */
    function uniTransfer(
        IERC20 token,
        address payable to,
        uint256 amount
    ) internal {
        if (amount > 0) {
            if (address(token) == _nativeToken) {
                uint256 contractBalance;
                assembly {
                    contractBalance := selfbalance()
                }
                if (contractBalance < amount) revert InsufficientBalance();
                (bool success, ) = to.call{
                    value: amount,
                    gas: _RAW_CALL_GAS_LIMIT
                }("");
                if (!success) revert NativeTransferFailed();
            } else {
                token.safeTransfer(to, amount);
            }
        } else {
            revert InsufficientBalance();
        }
    }

    /**
     * @notice Updates the gas limit for raw calls made by the contract.
     * @param gasLimit The new gas limit to be set.
     * @dev This function is restricted to the treasury.
     */
    function setGasLimit(uint256 gasLimit) external onlyTreasury {
        _RAW_CALL_GAS_LIMIT = gasLimit;
    }
}
