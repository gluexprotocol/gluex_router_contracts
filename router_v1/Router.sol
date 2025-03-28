// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {EthReceiver} from "./utils/EthReceiver.sol";
import {Interaction} from "./base/RouterStructs.sol";
import {IExecutor} from "./interfaces/IExecutor.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {SafeERC20} from "./lib/SafeERC20.sol";

/**
 * @title GluexRouter
 * @notice A versatile router contract that enables the execution of on-chain interactions using the `IExecutor` interface.
 * @dev This contract provides functionality for routing tokens through various interactions, collecting routing fees,
 *      and enforcing strict slippage and routing rules for optimal security and usability.
 */
contract GluexRouter is EthReceiver {
    using SafeERC20 for IERC20;

    // Errors
    error InsufficientBalance();
    error NativeTransferFailed();
    error OnlyGlueTreasury();
    error ZeroAddress();

    // Events
    /**
     * @notice Emitted when a routing operation is completed.
     * @param uniquePID The unique identifier for the partner.
     * @param userAddress The address of the user who initiated the route.
     * @param outputReceiver The address of the receiver of the output token.
     * @param inputToken The ERC20 token used as input.
     * @param inputAmount The amount of input token used for routing.
     * @param outputToken The ERC20 token received as output.
     * @param outputAmount The expected output amount from the route.
     * @param partnerFee The fee charged for the partner.
     * @param routingFee The fee charged for the routing operation.
     * @param finalOutputAmount The actual output amount received after routing.
     */
    event Routed(
        bytes indexed uniquePID,
        address indexed userAddress,
        address outputReceiver,
        IERC20 inputToken,
        uint256 inputAmount,
        IERC20 outputToken,
        uint256 outputAmount,
        uint256 partnerFee,
        uint256 routingFee,
        uint256 finalOutputAmount
    );

    // DataTypes
    /**
     * @dev A generic structure defining the parameters for a route.
     */
    struct RouteDescription {
        IERC20 inputToken; // Token used as input for the route
        IERC20 outputToken; // Token received as output from the route
        address payable inputReceiver; // Address to receive the input token
        address payable outputReceiver; // Address to receive the output token
        uint256 inputAmount; // Amount of input token
        uint256 outputAmount; // Original output amount
        uint256 partnerFee; // Fee for the partner
        uint256 routingFee; // Fee for the routing operation
        uint256 effectiveOutputAmount; // Effective output after deducting the routing fee
        uint256 minOutputAmount; // Minimum acceptable output amount
        bool isPermit2; // Whether to use Permit2 for token transfers
        bytes uniquePID; // Unique identifier for the partner
    }

    // Constants
    uint256 public _RAW_CALL_GAS_LIMIT = 5500;
    uint256 public _MAX_FEE = 15; // 11 bps (0.11%)
    uint256 public _MIN_FEE = 1; // 1 bps (0.01%)
    uint256 public _TOLERANCE = 1000;

    // State Variables
    address public immutable _nativeToken; // Address of the native token (e.g., Ether on Ethereum)
    address internal immutable _gluexTreasury; // Address of the GlueX treasury contract

    /**
     * @dev Initializes the contract with the treasury address and native token address.
     * @param gluexTreasury The address of the Glue treasury contract.
     * @param nativeToken The address of the native token.
     */
    constructor(address gluexTreasury, address nativeToken) {
        // Ensure the addresses are not zero
        checkZeroAddress(gluexTreasury);

        _gluexTreasury = gluexTreasury;
        _nativeToken = nativeToken;
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
        if (msg.sender != _gluexTreasury) revert OnlyGlueTreasury();
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
     * @notice Collects routing fees from specified tokens and transfers them to the given receiver.
     * @param feeTokens An array of ERC20 tokens from which fees will be collected.
     * @param receiver The address where collected fees will be transferred.
     */
    function collectFees(IERC20[] memory feeTokens, address payable receiver)
        external
        onlyTreasury
    {
        // Ensure the receiver address is valid
        checkZeroAddress(receiver);

        // Collect fees for each token
        uint256 len = feeTokens.length;
        for (uint256 i = 0; i < len; ) {
            uint256 feeBalance = uniBalanceOf(feeTokens[i], address(this));
            uniTransfer(feeTokens[i], receiver, feeBalance);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Executes a route using the specified executor and interactions.
     * @param executor The executor contract that performs the interactions.
     * @param desc The route description containing input, output, and fee details.
     * @param interactions The interactions encoded for execution by the executor.
     * @return finalOutputAmount The final amount of output token received.
     * @dev Ensures strict validation of slippage, routing fees, and input/output parameters.
     */
    function swap(
        IExecutor executor,
        RouteDescription calldata desc,
        Interaction[] calldata interactions,
        uint256 deadline
    ) external payable returns (uint256 finalOutputAmount) {
        // Deadline check
        if (block.timestamp > deadline) revert("Deadline passed");

        // Validate routing fee
        if (desc.routingFee > (desc.outputAmount * _MAX_FEE) / 10000) revert("Routing fee too high");
        if (desc.routingFee < (desc.outputAmount * _MIN_FEE) / 10000) revert("Routing fee too low");

        // Validate non-zero addresses
        checkZeroAddress(desc.inputReceiver);
        checkZeroAddress(desc.outputReceiver);

        // Validate route parameters
        if (desc.minOutputAmount <= 0) revert("Negative slippage limit");
        if (desc.minOutputAmount > desc.outputAmount) revert("Slippage limit too large");
        if (desc.inputToken == desc.outputToken) revert("Arbitrage not supported");
        if (desc.routingFee <= 0) revert("Negative routing fee");
        if (desc.partnerFee < 0) revert("Negative partner fee");
        if (
            desc.outputAmount <
            desc.effectiveOutputAmount +
                desc.partnerFee +
                desc.routingFee -
                _TOLERANCE ||
            desc.outputAmount >
            desc.effectiveOutputAmount +
                desc.partnerFee +
                desc.routingFee +
                _TOLERANCE
        ) revert("Invalid amounts");

        // Handle native token input validation
        if (address(desc.inputToken) == _nativeToken) {
            if (msg.value != desc.inputAmount) revert("Invalid native token input amount");
        } else {
            if (msg.value != 0) revert("Invalid native token input amount");
            desc.inputToken.safeTransferFromUniversal(
                msg.sender,
                desc.inputReceiver,
                desc.inputAmount,
                desc.isPermit2
            );
        }

        // Execute interactions through the executor
        uint256 outputBalanceBefore = uniBalanceOf(IERC20(desc.outputToken), address(this));
        IExecutor(executor).executeRoute{value: msg.value}(
            interactions,
            desc.outputToken
        );
        uint256 outputBalanceAfter = uniBalanceOf(IERC20(desc.outputToken), address(this));

        // Calculate final output amount
        uint256 routingFee = 0;
        if (outputBalanceAfter - outputBalanceBefore > desc.effectiveOutputAmount + desc.routingFee) {
            finalOutputAmount = outputBalanceAfter - outputBalanceBefore - desc.routingFee;
            routingFee = desc.routingFee;
        } else if (outputBalanceAfter - outputBalanceBefore > desc.effectiveOutputAmount) {
            finalOutputAmount = desc.effectiveOutputAmount;
            routingFee = outputBalanceAfter - outputBalanceBefore - desc.effectiveOutputAmount;
        } else {
            finalOutputAmount = outputBalanceAfter - outputBalanceBefore;
        }

        // Ensure final output amount meets the minimum required
        if (finalOutputAmount < desc.minOutputAmount) revert("Negative slippage too large");

        // Transfer the final output amount to the receiver
        uniTransfer(IERC20(desc.outputToken), desc.outputReceiver, finalOutputAmount);

        emit Routed(
            desc.uniquePID,
            msg.sender,
            desc.outputReceiver,
            desc.inputToken,
            desc.inputAmount,
            desc.outputToken,
            desc.outputAmount,
            desc.partnerFee,
            routingFee,
            finalOutputAmount
        );
    }

    /**
     * @notice Retrieves the balance of a specified token for a given account.
     * @param token The ERC20 token to check.
     * @param account The account address to query the balance for.
     * @return The balance of the token for the account.
     */
    function uniBalanceOf(IERC20 token, address account)
        internal
        view
        returns (uint256)
    {
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

    /**
     * @notice Updates the maximum fee that can be charged by the contract.
     * @param maxFee The new maximum fee to be set.
     * @dev This function is restricted to the treasury.
     */
    function setMaxFee(uint256 maxFee) external onlyTreasury {
        _MAX_FEE = maxFee;
    }

    /**
     * @notice Updates the minimum fee that can be charged by the contract.
     * @param minFee The new minimum fee to be set.
     * @dev This function is restricted to the treasury.
     */
    function setMinFee(uint256 minFee) external onlyTreasury {
        _MIN_FEE = minFee;
    }

    /**
     * @notice Updates the tolerance.
     * @param tolerance The new tolerance to be set.
     * @dev This function is restricted to the treasury.
     */
    function setTolerance(uint256 tolerance) external onlyTreasury {
        _TOLERANCE = tolerance;
    }
}