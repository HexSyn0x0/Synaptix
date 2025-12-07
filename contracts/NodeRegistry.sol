// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NodeRegistry
 * @notice Advanced DePIN node management for Synaptix (SYNX)
 * @dev Roles: DEFAULT_ADMIN_ROLE (governance), SLASHER_ROLE (punish), PAUSER_ROLE (pause).
 *      Features: staking, increase stake, withdrawal request + delay, partial withdrawal,
 *      slashing with multiplier, reputation, node list, network parameter updates, reentrancy guard.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract NodeRegistry is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IERC20 public immutable stakingToken;
    uint256 public minimumStake;
    uint256 public withdrawalDelay;          // seconds
    uint256 public maxReputation;
    uint256 public slashPenaltyMultiplier;   // e.g. 250 => 2.5% if divisor is 10000
    uint256 public constant SLASH_DIVISOR = 10000;

    enum NodeStatus { None, Active, CoolingDown, Inactive, Banned }

    struct Node {
        uint256 stakedAmount;
        uint256 reputation;
        uint256 registeredAt;
        uint256 lastRewardAt;
        uint256 withdrawUnlockTime; // timestamp when stake can be withdrawn
        NodeStatus status;
        bool exists;
    }

    // Storage
    mapping(address => Node) private nodes;
    address[] private nodeList;
    mapping(address => uint256) private nodeIndex; // 1-based index into nodeList for gas-efficient checks

    // Events
    event NodeRegistered(address indexed node, uint256 stake);
    event StakeIncreased(address indexed node, uint256 amount);
    event WithdrawalRequested(address indexed node, uint256 unlockTime);
    event StakeWithdrawn(address indexed node, uint256 amount);
    event NodeSlashed(address indexed node, uint256 amountSlashed, uint256 newReputation);
    event NodeStatusUpdated(address indexed node, NodeStatus newStatus);
    event ReputationUpdated(address indexed node, uint256 oldRep, uint256 newRep);
    event NetworkParametersUpdated(
        uint256 minimumStake,
        uint256 withdrawalDelay,
        uint256 maxReputation,
        uint256 slashPenaltyMultiplier
    );
    event NodeRemoved(address indexed node);

    // Constructor
    constructor(
        address _stakingToken,
        uint256 _minimumStake,
        uint256 _withdrawalDelay,
        uint256 _maxReputation,
        uint256 _slashPenaltyMultiplier
    ) {
        require(_stakingToken != address(0), "zero token");
        require(_maxReputation > 0, "invalid maxRep");

        stakingToken = IERC20(_stakingToken);
        minimumStake = _minimumStake;
        withdrawalDelay = _withdrawalDelay;
        maxReputation = _maxReputation;
        slashPenaltyMultiplier = _slashPenaltyMultiplier;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    // ---------------------
    // Modifiers / helpers
    // ---------------------
    modifier onlyExisting(address nodeAddr) {
        require(nodes[nodeAddr].exists, "node not registered");
        _;
    }

    // ---------------------
    // Node lifecycle
    // ---------------------
    function registerNode(uint256 amount) external whenNotPaused nonReentrant {
        require(amount >= minimumStake, "stake below minimum");
        Node storage n = nodes[msg.sender];
        require(!n.exists, "already registered");

        // transfer first to avoid reentrancy vector (safeTransferFrom will call ERC20)
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        n.stakedAmount = amount;
        n.reputation = maxReputation / 2; // start at 50% of max
        n.registeredAt = block.timestamp;
        n.lastRewardAt = block.timestamp;
        n.status = NodeStatus.Active;
        n.exists = true;

        nodeList.push(msg.sender);
        nodeIndex[msg.sender] = nodeList.length; // 1-based

        emit NodeRegistered(msg.sender, amount);
    }

    function increaseStake(uint256 amount) external whenNotPaused nonReentrant onlyExisting(msg.sender) {
        require(amount > 0, "zero amount");
        Node storage n = nodes[msg.sender];
        require(n.status != NodeStatus.Banned, "node banned");

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        n.stakedAmount += amount;

        emit StakeIncreased(msg.sender, amount);
    }

    // Request withdrawal -> sets CoolingDown and unlock time
    function requestWithdrawal() external whenNotPaused nonReentrant onlyExisting(msg.sender) {
        Node storage n = nodes[msg.sender];
        require(n.status == NodeStatus.Active, "not active");
        n.status = NodeStatus.CoolingDown;
        n.withdrawUnlockTime = block.timestamp + withdrawalDelay;

        emit WithdrawalRequested(msg.sender, n.withdrawUnlockTime);
        emit NodeStatusUpdated(msg.sender, NodeStatus.CoolingDown);
    }

    // Withdraw full stake after cooldown
    function withdrawStake() external nonReentrant onlyExisting(msg.sender) {
        Node storage n = nodes[msg.sender];
        require(n.status == NodeStatus.CoolingDown, "not cooling down");
        require(block.timestamp >= n.withdrawUnlockTime, "cooldown active");

        uint256 amount = n.stakedAmount;
        require(amount > 0, "no stake");

        // reset node
        n.stakedAmount = 0;
        n.status = NodeStatus.Inactive;
        n.exists = false;

        // remove from nodeList efficiently: swap & pop
        _removeNodeFromList(msg.sender);

        stakingToken.safeTransfer(msg.sender, amount);

        emit StakeWithdrawn(msg.sender, amount);
        emit NodeStatusUpdated(msg.sender, NodeStatus.Inactive);
    }

    // Allow partial withdrawal by governance (optional utility)
    function adminForceWithdraw(address nodeAddr, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant onlyExisting(nodeAddr) {
        Node storage n = nodes[nodeAddr];
        require(amount <= n.stakedAmount, "amount > stake");

        n.stakedAmount -= amount;
        stakingToken.safeTransfer(msg.sender /* admin */, amount);

        emit StakeWithdrawn(nodeAddr, amount);
    }

    // ---------------------
    // Slashing & reputation
    // ---------------------
    function slashNode(address nodeAddr, uint256 baseAmount) external onlyRole(SLASHER_ROLE) nonReentrant onlyExisting(nodeAddr) {
        Node storage n = nodes[nodeAddr];
        require(n.status != NodeStatus.Banned, "already banned");

        // compute penalty
        uint256 penalty = (baseAmount * slashPenaltyMultiplier) / SLASH_DIVISOR;
        uint256 totalSlash = baseAmount + penalty;

        if (totalSlash >= n.stakedAmount) {
            totalSlash = n.stakedAmount;
            n.stakedAmount = 0;
            n.status = NodeStatus.Banned;
        } else {
            n.stakedAmount -= totalSlash;
        }

        // degrade reputation safely
        uint256 oldRep = n.reputation;
        if (n.reputation > 0) {
            uint256 decrease = 10; // fixed or could be param
            n.reputation = (n.reputation > decrease) ? n.reputation - decrease : 0;
        }

        // slashed amount goes to slasher (or to treasury depending on design)
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
    // Governance / admin
    // ---------------------
    function changeNodeStatus(address nodeAddr, NodeStatus newStatus) external onlyRole(DEFAULT_ADMIN_ROLE) onlyExisting(nodeAddr) {
        nodes[nodeAddr].status = newStatus;
        emit NodeStatusUpdated(nodeAddr, newStatus);
    }

    function updateNetworkParameters(
        uint256 _minimumStake,
        uint256 _withdrawalDelay,
        uint256 _maxReputation,
        uint256 _slashPenaltyMultiplier
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minimumStake = _minimumStake;
        withdrawalDelay = _withdrawalDelay;
        maxReputation = _maxReputation;
        slashPenaltyMultiplier = _slashPenaltyMultiplier;

        emit NetworkParametersUpdated(_minimumStake, _withdrawalDelay, _maxReputation, _slashPenaltyMultiplier);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ---------------------
    // Views / utils
    // ---------------------
    function getNode(address nodeAddr) external view onlyExisting(nodeAddr) returns (Node memory) {
        return nodes[nodeAddr];
    }

    function getAllNodes() external view returns (address[] memory) {
        return nodeList;
    }

    function isNode(address addr) external view returns (bool) {
        return nodes[addr].exists;
    }

    // ---------------------
    // Internal helpers
    // ---------------------
    function _removeNodeFromList(address nodeAddr) internal {
        uint256 idx = nodeIndex[nodeAddr];
        require(idx != 0, "not indexed");
        uint256 listLen = nodeList.length;
        uint256 index0 = idx - 1;

        if (index0 != listLen - 1) {
            // swap with last
            address last = nodeList[listLen - 1];
            nodeList[index0] = last;
            nodeIndex[last] = idx; // moved to idx (1-based)
        }

        nodeList.pop();
        delete nodeIndex[nodeAddr];
        emit NodeRemoved(nodeAddr);
    }
}
