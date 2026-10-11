// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IDarkVerifier} from "dark-contracts/interfaces/IDarkVerifier.sol";
import {IDarkKeyRegistry} from "dark-contracts/interfaces/IDarkKeyRegistry.sol";
import {DarkVaultCore} from "./DarkVaultCore.sol";

/// @title DarkVault
/// @notice USDG <-> encrypted balances on Robinhood Chain: the contract deployed at
///         0xeD7a0c6899a6AC94Aea7A5b2F8f24a948042DA9C (chain 4663). The account paths live in
///         `DarkVaultCore`; this contract adds the owner functions (the owner is a 48-hour
///         TimelockController run by a 2-of-3 Safe), the guardian's emergency controls and the
///         views. No role here can move USDG or block an exit.
contract DarkVault is DarkVaultCore {
    using SafeERC20 for IERC20;

    constructor(
        address usdg_,
        IDarkKeyRegistry registry_,
        IDarkVerifier transferVerifier_,
        IDarkVerifier withdrawVerifier_,
        address owner_,
        address guardian_,
        Caps memory initialCaps
    ) DarkVaultCore(usdg_, registry_, transferVerifier_, withdrawVerifier_, owner_, guardian_, initialCaps) {}

    // ------------------------------------------------------------------ admin

    function setCaps(Caps calldata newCaps) external onlyOwner {
        _checkCeilings(newCaps);
        emit CapsUpdated(_caps, newCaps, msg.sender);
        _caps = newCaps;
    }

    function tightenCaps(Caps calldata newCaps) external {
        if (msg.sender != _guardian && msg.sender != owner()) revert NotGuardian();
        Caps memory c = _caps;
        bool ok = newCaps.maxDeposit <= c.maxDeposit && newCaps.maxAccountInflow <= c.maxAccountInflow
            && newCaps.maxTransfer <= c.maxTransfer && newCaps.tvlCap <= c.tvlCap && newCaps.minDeposit >= c.minDeposit
            && newCaps.minTransfer >= c.minTransfer;
        if (!ok) revert NotTightening();
        emit CapsUpdated(c, newCaps, msg.sender);
        _caps = newCaps;
    }

    function setGuardian(address guardian_) external onlyOwner {
        if (guardian_ == address(0)) revert ZeroAddress();
        emit GuardianUpdated(_guardian, guardian_);
        _guardian = guardian_;
    }

    /// @notice Blocks `deposit` and `transfer` only.
    function pause() external {
        if (msg.sender != _guardian && msg.sender != owner()) revert NotGuardian();
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function recoverERC20(address token, address to, uint256 amount) external onlyOwner {
        if (token == _usdg) revert CannotRecoverUSDG();
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
    }

    function renounceOwnership() public pure override {
        revert RenounceDisabled();
    }

    // ------------------------------------------------------------------ views

    function getAccount(address account) external view returns (AccountView memory) {
        Account storage a = _accounts[account];
        return AccountView(a.available, a.pending, a.nonce, a.pendingCount, a.netInflow, a.aeBalance);
    }

    function caps() external view returns (Caps memory) {
        return _caps;
    }

    function tvl() external view returns (uint256) {
        return _tvl;
    }

    function usdg() external view returns (address) {
        return _usdg;
    }

    function registry() external view returns (IDarkKeyRegistry) {
        return _registry;
    }

    function transferVerifier() external view returns (IDarkVerifier) {
        return _transferVerifier;
    }

    function withdrawVerifier() external view returns (IDarkVerifier) {
        return _withdrawVerifier;
    }

    function guardian() external view returns (address) {
        return _guardian;
    }

    function SPEC_VERSION() external pure returns (bytes32) {
        return keccak256("DARK-CB-1");
    }
}
