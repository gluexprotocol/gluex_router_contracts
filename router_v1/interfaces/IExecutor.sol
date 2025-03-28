// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Interaction} from "../base/RouterStructs.sol";
import {IERC20} from "./IERC20.sol";

/// @title Interface for making arbitrary calls
interface IExecutor {
    /// @notice propagates information about original msg.sender and executes arbitrary data
    function executeRoute(
        Interaction[] calldata interactions,
        IERC20 outputToken
    ) external payable;
}
