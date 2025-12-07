// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NodeManager
 * @notice Full-featured node management: staking, rewards, monitoring, slashing, emergency control.
 * @dev Integrates NodeRegistry, StakingRewardsAdvanced, and adds automatic monitoring & slashing.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

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
    function updateReputation(address nodeAddr, uint256 newRep) external;
    function slashNode(address nodeAddr, uint256 baseAmount) external;
    function nodeList() external view returns (address[] memory);
}

interface IStakingRewardsAdvanced {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
}

contract NodeManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    INodeRegistry public nodeRegistry;
    IStakingRewardsAdvanced public stakingRewards;

    // Monitoring parameters
    uint256 public maxAllowedDowntime; // seconds
    mapping(address => uint256) public lastActiveTimestamp;

    // Slashing parameters
    uint256 public baseSlashAmount; // fixed amount slashed for violations

    // Events
    event NodeMonitored(address indexed node, bool isActive, uint256 downtime);
    event NodeSlashedEvent(address indexed node, uint256 amount, uint256 newReputation);
    event EmergencyPause(address indexed admin);
    event EmergencyUnpause(address indexed admin);

    constructor(
        address _nodeRegistry,
        address _stakingRewards,
        uint256 _maxAllowedDowntime,
        uint256 _baseSlashAmount
    ) {
        require(_nodeRegistry != address(0), "zero node registry");
        require(_stakingRewards != address(0), "zero staking rewards");

        nodeRegistry = INodeRegistry(_nodeRegistry);
        stakingRewards = IStakingRewardsAdvanced(_stakingRewards);
        maxAllowedDowntime = _maxAllowedDowntime;
        baseSlashAmount = _baseSlashAmount;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SLASHER_ROLE, msg.sender);
    }

    // ---------------------
    // Node Monitoring
    // ---------------------
    function heartbeat() external whenNotPaused {
        require(nodeRegistry.isNode(msg.sender), "not a registered node");
        lastActiveTimestamp[msg.sender] = block.timestamp;
    }

    function monitorNode(address nodeAddr) public view returns (bool isActive, uint256 downtime) {
        uint256 lastActive = lastActiveTimestamp[nodeAddr];
        if (lastActive == 0) lastActive = block.timestamp; // default to now if never heartbeat
        downtime = block.timestamp - lastActive;
        isActive = downtime <= maxAllowedDowntime;
    }

    function checkAndSlash(address nodeAddr) external onlyRole(SLASHER_ROLE) whenNotPaused {
        (bool isActive, uint256 downtime) = monitorNode(nodeAddr);
        if (!isActive) {
            // apply slashing via NodeRegistry
            nodeRegistry.slashNode(nodeAddr, baseSlashAmount);

            // update reputation
            (, uint256 oldRep,, , , ,) = nodeRegistry.getNode(nodeAddr);
            uint256 newRep = oldRep > 0 ? oldRep - 5 : 0; // reduce 5 points reputation
            nodeRegistry.updateReputation(nodeAddr, newRep);

            emit NodeSlashedEvent(nodeAddr, baseSlashAmount, newRep);
        }
        emit NodeMonitored(nodeAddr, isActive, downtime);
    }

    function massMonitorAndSlash() external onlyRole(SLASHER_ROLE) whenNotPaused {
        address[] memory nodes = nodeRegistry.nodeList();
        for (uint256 i = 0; i < nodes.length; i++) {
            checkAndSlash(nodes[i]);
        }
    }

    // ---------------------
    // Emergency controls
    // ---------------------
    function emergencyPause() external onlyRole(ADMIN_ROLE) {
        _pause();
        emit EmergencyPause(msg.sender);
    }

    function emergencyUnpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
        emit EmergencyUnpause(msg.sender);
    }

    // ---------------------
    // Integration with staking rewards
    // ---------------------
    function stake(uint256 amount) external whenNotPaused {
        require(nodeRegistry.isNode(msg.sender), "not a registered node");
        stakingRewards.stake(amount);
    }

    function withdraw(uint256 amount) external whenNotPaused {
        require(nodeRegistry.isNode(msg.sender), "not a registered node");
        stakingRewards.withdraw(amount);
    }

    function claimReward() external whenNotPaused {
        require(nodeRegistry.isNode(msg.sender), "not a registered node");
        stakingRewards.getReward();
    }

    // ---------------------
    // Admin functions
    // ---------------------
    function setMaxAllowedDowntime(uint256 _seconds) external onlyRole(ADMIN_ROLE) {
        maxAllowedDowntime = _seconds;
    }

    function setBaseSlashAmount(uint256 _amount) external onlyRole(ADMIN_ROLE) {
        baseSlashAmount = _amount;
    }
}
