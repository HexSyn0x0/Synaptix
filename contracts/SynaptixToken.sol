// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SynaptixToken (SYNX)
 * @notice ERC-20 token for the Synaptix ecosystem with fixed supply and preset distribution.
 * @dev Uses OpenZeppelin ERC20 base. Total supply = 100,000,000 SYNX.
 *      Distribution:
 *        - 60% Presale
 *        - 15% Liquidity
 *        - 5% Team & Partnerships
 *        - 20% Node Rewards
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SynaptixToken is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 1e18; // 100M SYNX, 18 decimals

    // Preset wallet addresses for distribution
    address public presaleWallet;
    address public liquidityWallet;
    address public teamWallet;
    address public nodeRewardsWallet;

    constructor(
        address _presaleWallet,
        address _liquidityWallet,
        address _teamWallet,
        address _nodeRewardsWallet
    ) ERC20("Synaptix", "SYNX") {
        require(_presaleWallet != address(0), "Invalid presale wallet");
        require(_liquidityWallet != address(0), "Invalid liquidity wallet");
        require(_teamWallet != address(0), "Invalid team wallet");
        require(_nodeRewardsWallet != address(0), "Invalid node rewards wallet");

        presaleWallet = _presaleWallet;
        liquidityWallet = _liquidityWallet;
        teamWallet = _teamWallet;
        nodeRewardsWallet = _nodeRewardsWallet;

        // Distribute tokens according to tokenomics
        _mint(presaleWallet, (TOTAL_SUPPLY * 60) / 100);       // 60% Presale
        _mint(liquidityWallet, (TOTAL_SUPPLY * 15) / 100);     // 15% Liquidity
        _mint(teamWallet, (TOTAL_SUPPLY * 5) / 100);           // 5% Team & Partnerships
        _mint(nodeRewardsWallet, (TOTAL_SUPPLY * 20) / 100);  // 20% Node Rewards
    }
}
