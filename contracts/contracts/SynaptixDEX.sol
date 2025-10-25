// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SynaptixDEX (Advanced WIP)
 * @notice Decentralized perpetual futures exchange with leverage trading, multi-collateral architecture, and advanced liquidation system.
 * @dev This contract includes skeletons for future features inspired by Hyperliquid:
 *      - Multi-collateral support
 *      - Dynamic fee model
 *      - Advanced liquidation with partial closing
 *      - Oracle integration for real-time pricing
 *      - MEV protection / anti front-running
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SynaptixDEX is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ---------------------
    // Structs & Storage
    // ---------------------
    struct Position {
        int256 size;           // Positive = long, negative = short
        uint256 collateral;    // Collateral in SYNX or future multi-collateral tokens
        uint256 entryPrice;
        uint256 leverage;
        bool isActive;
    }

    struct Collateral {
        IERC20 token;
        uint256 factor; // Used for multi-collateral weighting
    }

    mapping(address => Position) public positions;
    mapping(address => Collateral) public collateralTypes;

    IERC20 public defaultTokenA;
    IERC20 public defaultTokenB;

    uint256 public leverageLimit = 5; // Max 5x leverage
    uint256 public baseFee = 50;      // 0.5% base fee
    uint256 public liquidationThreshold = 95; // 95% of collateral

    // ---------------------
    // Events
    // ---------------------
    event PositionOpened(address indexed user, int256 size, uint256 collateral, uint256 entryPrice);
    event PositionClosed(address indexed user, int256 size, uint256 pnl);
    event PositionLiquidated(address indexed user, int256 size, uint256 pnl);
    event CollateralAdded(address indexed token, uint256 factor);

    // ---------------------
    // Constructor
    // ---------------------
    constructor(address _tokenA, address _tokenB) {
        defaultTokenA = IERC20(_tokenA);
        defaultTokenB = IERC20(_tokenB);
    }

    // ---------------------
    // Position Management
    // ---------------------
    function openPosition(
        int256 size,
        uint256 collateral,
        uint256 entryPrice,
        uint256 leverage
    ) external nonReentrant {
        require(size != 0, "Size cannot be 0");
        require(collateral > 0, "Collateral must be > 0");
        require(leverage <= leverageLimit, "Leverage too high");
        require(abs(size) <= int256(collateral * leverage), "Position size exceeds leverage");

        // Transfer collateral to contract (currently using defaultTokenA)
        defaultTokenA.safeTransferFrom(msg.sender, address(this), collateral);

        // Update user position
        Position storage pos = positions[msg.sender];
        pos.size += size;
        pos.collateral += collateral;
        pos.entryPrice = entryPrice;
        pos.leverage = leverage;
        pos.isActive = true;

        emit PositionOpened(msg.sender, size, collateral, entryPrice);
    }

    function closePosition(int256 size, uint256 exitPrice) external nonReentrant {
        Position storage pos = positions[msg.sender];
        require(pos.isActive, "No active position");
        require(abs(size) <= abs(pos.size), "Closing too much");

        int256 pnl = calculatePnL(pos.size, pos.entryPrice, exitPrice);
        pos.size -= size;
        if (pos.size == 0) pos.isActive = false;

        uint256 payout = uint256(pos.collateral + uint256(pnl));
        defaultTokenA.safeTransfer(msg.sender, payout);

        emit PositionClosed(msg.sender, size, pnl);
    }

    function liquidate(address user, uint256 price) external onlyOwner {
        Position storage pos = positions[user];
        require(pos.isActive, "No active position");

        int256 pnl = calculatePnL(pos.size, pos.entryPrice, price);
        if (pnl < -int256(pos.collateral * liquidationThreshold / 100)) {
            pos.isActive = false;
            uint256 payout = uint256(pos.collateral + uint256(pnl));
            defaultTokenA.safeTransfer(owner(), payout);
            emit PositionLiquidated(user, pos.size, uint256(pnl));
        }
    }

    // ---------------------
    // Multi-collateral (WIP)
    // ---------------------
    function addCollateralType(address token, uint256 factor) external onlyOwner {
        collateralTypes[token] = Collateral(IERC20(token), factor);
        emit CollateralAdded(token, factor);
    }

    // ---------------------
    // Fee System (WIP)
    // ---------------------
    function calculateFee(uint256 amount) public view returns (uint256) {
        // Placeholder for dynamic fee calculation
        return (amount * baseFee) / 10000;
    }

    // ---------------------
    // Oracle integration (WIP)
    // ---------------------
    function getPriceFromOracle(IERC20 token) internal view returns (uint256) {
        // TODO: integrate real oracle
        return 1e18; // placeholder
    }

    // ---------------------
    // Internal Helpers
    // ---------------------
    function calculatePnL(int256 size, uint256 entryPrice, uint256 exitPrice) internal pure returns (int256) {
        if (size > 0) {
            return int256(size) * int256(exitPrice - entryPrice) / int256(entryPrice);
        } else {
            return int256(-size) * int256(entryPrice - exitPrice) / int256(entryPrice);
        }
    }

    function abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }
}
