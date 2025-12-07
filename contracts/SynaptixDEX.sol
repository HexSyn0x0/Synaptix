// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SynaptixDEX (Advanced)
 * @notice Decentralized perpetual futures exchange with leverage trading, multi-collateral, funding rate, advanced liquidation, and decentralized nodes integration.
 * @dev Integrates NodeRegistry for node validation and staking rewards.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface INodeRegistry {
    function isNode(address nodeAddr) external view returns (bool);
    function getNode(address nodeAddr) external view returns (
        uint256 stakedAmount,
        uint256 reputation,
        uint256 registeredAt,
        uint256 lastRewardAt,
        uint256 withdrawUnlockTime,
        uint8 status,
        bool exists
    );
}

contract SynaptixDEX is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ---------------------
    // Structs & Storage
    // ---------------------
    struct Position {
        int256 size;           // Positive = long, negative = short
        uint256 collateral;    // Collateral in SYNX or multi-collateral tokens
        uint256 entryPrice;
        uint256 leverage;
        bool isActive;
        uint256 lastFundingPaid;
    }

    struct Collateral {
        IERC20 token;
        uint256 factor; // for multi-collateral weighting
    }

    mapping(address => Position) public positions;
    mapping(address => Collateral) public collateralTypes;

    IERC20 public defaultToken;

    uint256 public leverageLimit = 5;               // Max leverage
    uint256 public baseFee = 50;                   // 0.5%
    uint256 public liquidationThreshold = 95;      // 95% collateral
    int256 public fundingRatePerHour = 10;         // 0.1% per hour funding

    INodeRegistry public nodeRegistry;

    // ---------------------
    // Events
    // ---------------------
    event PositionOpened(address indexed user, int256 size, uint256 collateral, uint256 entryPrice);
    event PositionClosed(address indexed user, int256 size, int256 pnl);
    event PositionLiquidated(address indexed user, int256 size, int256 pnl);
    event CollateralAdded(address indexed token, uint256 factor);
    event FeeUpdated(uint256 baseFee);
    event FundingPaid(address indexed user, int256 funding);

    // ---------------------
    // Constructor
    // ---------------------
    constructor(address _defaultToken, address _nodeRegistry) {
        require(_defaultToken != address(0), "zero token");
        require(_nodeRegistry != address(0), "zero registry");
        defaultToken = IERC20(_defaultToken);
        nodeRegistry = INodeRegistry(_nodeRegistry);
    }

    // ---------------------
    // Collateral Management
    // ---------------------
    function addCollateralType(address token, uint256 factor) external onlyOwner {
        collateralTypes[token] = Collateral(IERC20(token), factor);
        emit CollateralAdded(token, factor);
    }

    // ---------------------
    // Position Management
    // ---------------------
    function openPosition(int256 size, uint256 collateral, uint256 entryPrice, uint256 leverage) external nonReentrant {
        require(nodeRegistry.isNode(msg.sender), "only registered nodes can trade");
        require(size != 0, "size cannot be 0");
        require(collateral > 0, "collateral > 0");
        require(leverage <= leverageLimit, "leverage too high");
        require(abs(size) <= int256(collateral * leverage), "position size exceeds leverage");

        // Transfer collateral
        defaultToken.safeTransferFrom(msg.sender, address(this), collateral);

        // Update position
        Position storage pos = positions[msg.sender];
        pos.size += size;
        pos.collateral += collateral;
        pos.entryPrice = entryPrice;
        pos.leverage = leverage;
        pos.isActive = true;
        pos.lastFundingPaid = block.timestamp;

        emit PositionOpened(msg.sender, size, collateral, entryPrice);
    }

    function closePosition(int256 size, uint256 exitPrice) external nonReentrant {
        Position storage pos = positions[msg.sender];
        require(pos.isActive, "no active position");
        require(abs(size) <= abs(pos.size), "closing too much");

        // Calculate funding payment and PnL
        int256 funding = calculateFunding(pos);
        int256 pnl = calculatePnL(pos.size, pos.entryPrice, exitPrice) - funding;

        pos.size -= size;
        if (pos.size == 0) pos.isActive = false;
        pos.lastFundingPaid = block.timestamp;

        uint256 payout = uint256(pos.collateral + uint256(pnl));
        defaultToken.safeTransfer(msg.sender, payout);

        emit FundingPaid(msg.sender, funding);
        emit PositionClosed(msg.sender, size, pnl);
    }

    function liquidate(address user, uint256 price) external onlyOwner {
        Position storage pos = positions[user];
        require(pos.isActive, "no active position");

        int256 funding = calculateFunding(pos);
        int256 pnl = calculatePnL(pos.size, pos.entryPrice, price) - funding;

        if (pnl < -int256(pos.collateral * liquidationThreshold / 100)) {
            pos.isActive = false;
            uint256 payout = uint256(pos.collateral + uint256(pnl));
            defaultToken.safeTransfer(owner(), payout);
            emit FundingPaid(user, funding);
            emit PositionLiquidated(user, pos.size, pnl);
        }
    }

    // ---------------------
    // Funding Rate
    // ---------------------
    function calculateFunding(Position memory pos) public view returns (int256) {
        uint256 hoursElapsed = (block.timestamp - pos.lastFundingPaid) / 3600;
        int256 funding = int256(pos.size) * fundingRatePerHour * int256(hoursElapsed) / 10000;
        return funding;
    }

    function payFunding() external {
        Position storage pos = positions[msg.sender];
        require(pos.isActive, "no active position");
        int256 funding = calculateFunding(pos);
        pos.lastFundingPaid = block.timestamp;

        if (funding > 0) {
            defaultToken.safeTransferFrom(msg.sender, address(this), uint256(funding));
        } else if (funding < 0) {
            defaultToken.safeTransfer(msg.sender, uint256(-funding));
        }
        emit FundingPaid(msg.sender, funding);
    }

    // ---------------------
    // Fee system
    // ---------------------
    function calculateFee(uint256 amount) public view returns (uint256) {
        return (amount * baseFee) / 10000;
    }

    function setBaseFee(uint256 fee) external onlyOwner {
        baseFee = fee;
        emit FeeUpdated(fee);
    }

    // ---------------------
    // Helpers
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
