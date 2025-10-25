// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NodeRegistry
 * @notice Manages DePIN nodes, their staking, status, and penalties.
 * @dev Each node must stake SYNX tokens to participate. Admin can slash or ban nodes.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NodeRegistry is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public stakingToken;
    uint256 public minimumStake;

    enum NodeStatus { Active, Inactive, Banned }

    struct Node {
        uint256 stakedAmount;
        NodeStatus status;
        uint256 registeredAt;
    }

    mapping(address => Node) public nodes;
    address[] public nodeList;

    event NodeRegistered(address indexed node, uint256 amount);
    event NodeSlashed(address indexed node, uint256 amount);
    event NodeStatusChanged(address indexed node, NodeStatus status);
    event NodeUnstaked(address indexed node, uint256 amount);

    constructor(address _stakingToken, uint256 _minimumStake) {
        stakingToken = IERC20(_stakingToken);
        minimumStake = _minimumStake;
    }

    // ---------------------
    // Node operations
    // ---------------------
    function registerNode(uint256 amount) external {
        require(amount >= minimumStake, "Stake below minimum");
        Node storage node = nodes[msg.sender];
        require(node.stakedAmount == 0, "Node already registered");

        node.stakedAmount = amount;
        node.status = NodeStatus.Active;
        node.registeredAt = block.timestamp;
        nodeList.push(msg.sender);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit NodeRegistered(msg.sender, amount);
    }

    function slashNode(address nodeAddr, uint256 amount) external onlyOwner {
        Node storage node = nodes[nodeAddr];
        require(node.status != NodeStatus.Banned, "Node already banned");
        require(amount <= node.stakedAmount, "Slash amount too high");

        node.stakedAmount -= amount;
        stakingToken.safeTransfer(owner(), amount);
        emit NodeSlashed(nodeAddr, amount);
    }

    function changeNodeStatus(address nodeAddr, NodeStatus newStatus) external onlyOwner {
        Node storage node = nodes[nodeAddr];
        node.status = newStatus;
        emit NodeStatusChanged(nodeAddr, newStatus);
    }

    function unstakeNode() external {
        Node storage node = nodes[msg.sender];
        require(node.stakedAmount > 0, "No stake found");
        require(node.status != NodeStatus.Banned, "Banned nodes cannot unstake");

        uint256 amount = node.stakedAmount;
        node.stakedAmount = 0;
        node.status = NodeStatus.Inactive;

        stakingToken.safeTransfer(msg.sender, amount);
        emit NodeUnstaked(msg.sender, amount);
    }

    // ---------------------
    // Views
    // ---------------------
    function getNode(address nodeAddr) external view returns (Node memory) {
        return nodes[nodeAddr];
    }

    function getAllNodes() external view returns (address[] memory) {
        return nodeList;
    }
}
