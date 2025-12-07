// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title StakingRewards
 * @notice Allows registered Synaptix nodes to stake SYNX tokens and earn rewards over time.
 * @dev Integrates seamlessly with NodeRegistry. Uses OpenZeppelin libraries for security.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

interface INodeRegistry {
    function isNode(address nodeAddr) external view returns (bool);
}

contract StakingRewards is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IERC20 public immutable stakingToken;   // SYNX token
    IERC20 public immutable rewardToken;    // SYNX token for rewards

    uint256 public rewardRate;              // reward tokens per second
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

    INodeRegistry public nodeRegistry;

    // Events
    event Staked(address indexed node, uint256 amount);
    event Withdrawn(address indexed node, uint256 amount);
    event RewardPaid(address indexed node, uint256 reward);
    event RewardRateUpdated(uint256 newRate);
    event NodeRegistryUpdated(address newRegistry);

    constructor(
        address _stakingToken,
        address _rewardToken,
        address _nodeRegistry,
        uint256 _rewardRate
    ) {
        require(_stakingToken != address(0), "zero staking token");
        require(_rewardToken != address(0), "zero reward token");
        require(_nodeRegistry != address(0), "zero node registry");

        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        nodeRegistry = INodeRegistry(_nodeRegistry);
        rewardRate = _rewardRate;
        lastUpdateTime = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    // ---------------------
    // Internal reward logic
    // ---------------------
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) return rewardPerTokenStored;
        return
            rewardPerTokenStored +
            ((block.timestamp - lastUpdateTime) * rewardRate * 1e18 / _totalSupply);
    }

    function earned(address account) public view returns (uint256) {
        return (_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18) + rewards[account];
    }

    function _updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    // ---------------------
    // Node staking functions
    // ---------------------
    function stake(uint256 amount) external nonReentrant {
        require(nodeRegistry.isNode(msg.sender), "not a registered node");
        require(amount > 0, "cannot stake 0");
        _updateReward(msg.sender);

        _totalSupply += amount;
        _balances[msg.sender] += amount;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant {
        require(nodeRegistry.isNode(msg.sender), "not a registered node");
        require(amount > 0, "cannot withdraw 0");
        _updateReward(msg.sender);

        _totalSupply -= amount;
        _balances[msg.sender] -= amount;

        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function claimReward() public nonReentrant {
        require(nodeRegistry.isNode(msg.sender), "not a registered node");
        _updateReward(msg.sender);

        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        claimReward();
    }

    // ---------------------
    // Admin functions
    // ---------------------
    function setRewardRate(uint256 _rewardRate) external onlyRole(ADMIN_ROLE) {
        _updateReward(address(0));
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    function setNodeRegistry(address _nodeRegistry) external onlyRole(ADMIN_ROLE) {
        require(_nodeRegistry != address(0), "zero address");
        nodeRegistry = INodeRegistry(_nodeRegistry);
        emit NodeRegistryUpdated(_nodeRegistry);
    }

    function recoverERC20(address tokenAddress, uint256 amount) external onlyRole(ADMIN_ROLE) {
        IERC20(tokenAddress).safeTransfer(msg.sender, amount);
    }

    // ---------------------
    // Views
    // ---------------------
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function rewardsOf(address account) external view returns (uint256) {
        return earned(account);
    }
}
