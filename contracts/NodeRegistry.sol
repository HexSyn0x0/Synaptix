// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title NodeRegistry
 * @notice Node management contract for staking, rewards, heartbeat, slashing, and governance
 * @dev Roles:
 *      DEFAULT_ADMIN_ROLE - network governance
 *      SLASHER_ROLE - slashing misbehaving nodes
 *      PAUSER_ROLE - pause/unpause contract in emergencies
 */
contract NodeRegistry is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ---------------------
    // Roles
    // ---------------------
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ---------------------
    // Network parameters
    // ---------------------
    IERC20 public immutable stakingToken;
    uint256 public minimumStake;
    uint256 public withdrawalDelay;          
    uint256 public maxReputation;
    uint256 public slashPenaltyMultiplier;   
    uint256 public constant SLASH_DIVISOR = 10000;
    uint256 public heartbeatInterval;
    uint256 public partialWithdrawalCooldown;

    // ---------------------
    // Node data structures
    // ---------------------
    enum NodeStatus { None, Active, CoolingDown, Inactive, Banned }

    struct Node {
        uint256 stakedAmount;
        uint256 reputation;
        uint256 registeredAt;
        uint256 lastRewardAt;
        uint256 withdrawUnlockTime;
        uint256 lastHeartbeat;
        uint256 lastPartialWithdrawal;
        NodeStatus status;
        bool exists;
    }

    mapping(address => Node) private nodes;
    address[] private nodeList;
    mapping(address => uint256) private nodeIndex;

    // ---------------------
    // Events
    // ---------------------
    event NodeRegistered(address indexed node, uint256 stake);
    event StakeIncreased(address indexed node, uint256 amount);
    event WithdrawalRequested(address indexed node, uint256 unlockTime);
    event PartialWithdrawalRequested(address indexed node, uint256 amount, uint256 unlockTime);
    event StakeWithdrawn(address indexed node, uint256 amount);
    event NodeSlashed(address indexed node, uint256 amountSlashed, uint256 newReputation);
    event NodeStatusUpdated(address indexed node, NodeStatus newStatus);
    event ReputationUpdated(address indexed node, uint256 oldRep, uint256 newRep);
    event NetworkParametersUpdated(
        uint256 minimumStake,
        uint256 withdrawalDelay,
        uint256 maxReputation,
        uint256 slashPenaltyMultiplier,
        uint256 heartbeatInterval,
        uint256 partialWithdrawalCooldown
    );
    event NodeRemoved(address indexed node);
    event RewardDistributed(address indexed node, uint256 amount);
    event Heartbeat(address indexed node, uint256 timestamp);

    // ---------------------
    // Constructor
    // ---------------------
    constructor(
        address _stakingToken,
        uint256 _minimumStake,
        uint256 _withdrawalDelay,
        uint256 _maxReputation,
        uint256 _slashPenaltyMultiplier,
        uint256 _heartbeatInterval,
        uint256 _partialWithdrawalCooldown
    ) {
        require(_stakingToken != address(0), "zero token");
        require(_maxReputation > 0, "invalid maxRep");

        stakingToken = IERC20(_stakingToken);
        minimumStake = _minimumStake;
        withdrawalDelay = _withdrawalDelay;
        maxReputation = _maxReputation;
        slashPenaltyMultiplier = _slashPenaltyMultiplier;
        heartbeatInterval = _heartbeatInterval;
        partialWithdrawalCooldown = _partialWithdrawalCooldown;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    // ---------------------
    // Modifiers
    // ---------------------
    modifier onlyExisting(address nodeAddr) {
        require(nodes[nodeAddr].exists, "node not registered");
        _;
    }

    modifier onlyActive(address nodeAddr) {
        require(nodes[nodeAddr].status == NodeStatus.Active, "node not active");
        _;
    }

    // ---------------------
    // Node lifecycle
    // ---------------------
    function registerNode(uint256 amount) external whenNotPaused nonReentrant {
        Node storage n = nodes[msg.sender];
        require(!n.exists, "already registered");
        require(amount >= minimumStake, "stake below minimum");

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        n.stakedAmount = amount;
        n.reputation = maxReputation / 2;
        n.registeredAt = block.timestamp;
        n.lastRewardAt = block.timestamp;
        n.lastHeartbeat = block.timestamp;
        n.status = NodeStatus.Active;
        n.exists = true;

        nodeList.push(msg.sender);
        nodeIndex[msg.sender] = nodeList.length;

        emit NodeRegistered(msg.sender, amount);
    }

    function increaseStake(uint256 amount) external whenNotPaused nonReentrant onlyExisting(msg.sender) {
        Node storage n = nodes[msg.sender];
        require(n.status != NodeStatus.Banned, "node banned");
        require(amount > 0, "zero amount");

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        n.stakedAmount += amount;

        emit StakeIncreased(msg.sender, amount);
    }

    function requestWithdrawal() external whenNotPaused nonReentrant onlyActive(msg.sender) {
        Node storage n = nodes[msg.sender];
        n.status = NodeStatus.CoolingDown;
        n.withdrawUnlockTime = block.timestamp + withdrawalDelay;

        emit WithdrawalRequested(msg.sender, n.withdrawUnlockTime);
        emit NodeStatusUpdated(msg.sender, NodeStatus.CoolingDown);
    }

    function requestPartialWithdrawal(uint256 amount) external whenNotPaused nonReentrant onlyActive(msg.sender) {
        Node storage n = nodes[msg.sender];
        require(amount > 0 && amount <= n.stakedAmount, "invalid amount");
        require(block.timestamp >= n.lastPartialWithdrawal + partialWithdrawalCooldown, "cooldown active");

        n.stakedAmount -= amount;
        n.lastPartialWithdrawal = block.timestamp;
        stakingToken.safeTransfer(msg.sender, amount);

        emit PartialWithdrawalRequested(msg.sender, amount, block.timestamp + partialWithdrawalCooldown);
    }

    function withdrawStake() external nonReentrant onlyExisting(msg.sender) {
        Node storage n = nodes[msg.sender];
        require(n.status == NodeStatus.CoolingDown, "not cooling down");
        require(block.timestamp >= n.withdrawUnlockTime, "cooldown active");

        uint256 amount = n.stakedAmount;
        n.stakedAmount = 0;
        n.status = NodeStatus.Inactive;
        n.exists = false;

        _removeNodeFromList(msg.sender);
        stakingToken.safeTransfer(msg.sender, amount);

        emit StakeWithdrawn(msg.sender, amount);
        emit NodeStatusUpdated(msg.sender, NodeStatus.Inactive);
    }

    // ---------------------
    // Rewards Engine
    // ---------------------
    function distributeRewards(address nodeAddr, uint256 rewardAmount) external onlyRole(DEFAULT_ADMIN_ROLE) onlyActive(nodeAddr) {
        Node storage n = nodes[nodeAddr];
        n.lastRewardAt = block.timestamp;
        stakingToken.safeTransfer(nodeAddr, rewardAmount);
        emit RewardDistributed(nodeAddr, rewardAmount);
    }

    // ---------------------
    // Node Monitoring / Heartbeat
    // ---------------------
    function sendHeartbeat() external onlyActive(msg.sender) {
        Node storage n = nodes[msg.sender];
        n.lastHeartbeat = block.timestamp;
        emit Heartbeat(msg.sender, block.timestamp);
    }

    function checkHeartbeat(address nodeAddr) external view onlyExisting(nodeAddr) returns (bool) {
        Node storage n = nodes[nodeAddr];
        return (block.timestamp - n.lastHeartbeat) <= heartbeatInterval;
    }

    // ---------------------
    // Slashing & Reputation
    // ---------------------
    function slashNode(address nodeAddr, uint256 baseAmount) external onlyRole(SLASHER_ROLE) nonReentrant onlyExisting(nodeAddr) {
        Node storage n = nodes[nodeAddr];
        require(n.status != NodeStatus.Banned, "already banned");

        uint256 penalty = (baseAmount * slashPenaltyMultiplier) / SLASH_DIVISOR;
        uint256 totalSlash = baseAmount + penalty;

        if (totalSlash >= n.stakedAmount) {
            totalSlash = n.stakedAmount;
            n.stakedAmount = 0;
            n.status = NodeStatus.Banned;
        } else {
            n.stakedAmount -= totalSlash;
        }

        uint256 oldRep = n.reputation;
        if (n.reputation > 0) {
            uint256 decrease = 10;
            n.reputation = (n.reputation > decrease) ? n.reputation - decrease : 0;
        }

        stakingToken.safeTransfer(msg.sender, totalSlash);

        emit NodeSlashed(nodeAddr, totalSlash, n.reputation);
        emit ReputationUpdated(nodeAddr, oldRep, n.reputation);
        emit NodeStatusUpdated(nodeAddr, n.status);
    }

    function updateReputation(address nodeAddr, uint256 newRep) external onlyRole(DEFAULT_ADMIN_ROLE) onlyExisting(nodeAddr) {
        require(newRep <= maxReputation, "exceeds max");
        uint256 oldRep = nodes[nodeAddr].reputation;
        nodes[nodeAddr].reputation = newRep;
        emit ReputationUpdated(nodeAddr, oldRep, newRep);
    }

    // ---------------------
    // Governance / Admin
    // ---------------------
    function changeNodeStatus(address nodeAddr, NodeStatus newStatus) external onlyRole(DEFAULT_ADMIN_ROLE) onlyExisting(nodeAddr) {
        nodes[nodeAddr].status = newStatus;
        emit NodeStatusUpdated(nodeAddr, newStatus);
    }

    function updateNetworkParameters(
        uint256 _minimumStake,
        uint256 _withdrawalDelay,
        uint256 _maxReputation,
        uint256 _slashPenaltyMultiplier,
        uint256 _heartbeatInterval,
        uint256 _partialWithdrawalCooldown
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minimumStake = _minimumStake;
        withdrawalDelay = _withdrawalDelay;
        maxReputation = _maxReputation;
        slashPenaltyMultiplier = _slashPenaltyMultiplier;
        heartbeatInterval = _heartbeatInterval;
        partialWithdrawalCooldown = _partialWithdrawalCooldown;

        emit NetworkParametersUpdated(
            _minimumStake, _withdrawalDelay, _maxReputation, _slashPenaltyMultiplier, _heartbeatInterval, _partialWithdrawalCooldown
        );
    }

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // ---------------------
    // Views / Utils
    // ---------------------
    function getNode(address nodeAddr) external view onlyExisting(nodeAddr) returns (Node memory) { return nodes[nodeAddr]; }
    function getAllNodes() external view returns (address[] memory) { return nodeList; }
    function isNode(address addr) external view returns (bool) { return nodes[addr].exists; }

    // ---------------------
    // Internal Helpers
    // ---------------------
    function _removeNodeFromList(address nodeAddr) internal {
        uint256 idx = nodeIndex[nodeAddr];
        require(idx != 0, "not indexed");
        uint256 listLen = nodeList.length;
        uint256 index0 = idx - 1;

        if (index0 != listLen - 1) {
            address last = nodeList[listLen - 1];
            nodeList[index0] = last;
            nodeIndex[last] = idx;
        }

        nodeList.pop();
        delete nodeIndex[nodeAddr];
        emit NodeRemoved(nodeAddr);
    }
}
