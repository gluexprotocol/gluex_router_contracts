// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/**
 * @dev Generic interface for native tokens.
 *
 * Note that this interface may require adjustment
 * per chain. 
 */
 interface IWrappedNativeToken {
    /**
     * @dev Returns amount deposited into native wrapper.
     */
    function deposit() external payable;

    /**
     * @dev Returns amount withdrawn from native wrapper.
     */
    function withdraw(uint wad) external;
 }