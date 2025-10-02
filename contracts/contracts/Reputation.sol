// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Reputation
 * @notice Tracks user reputation across ChainCircle platform
 * @dev Reputation is earned through successful circle participation
 */
contract Reputation is Ownable {
    
    // ============ Structs ============
    
    struct UserReputation {
        uint256 circlesCompleted;
        uint256 circlesActive;
        uint256 totalContributed;
        uint256 onTimePayments;
        uint256 missedPayments;
        uint256 accountCreated;
        uint256 lastActive;
        uint256 reputationScore;
        ReputationTier tier;
    }
    
    // ============ Enums ============
    
    enum ReputationTier {
        BRONZE,      // 0-249 points
        SILVER,      // 250-499 points
        GOLD,        // 500-749 points
        PLATINUM,    // 750-999 points
        DIAMOND      // 1000+ points
    }
    
    // ============ State Variables ============
    
    mapping(address => UserReputation) public userReputations;
    mapping(address => bool) public authorizedCallers; // ChainCircle contract can update
    
    // Scoring weights
    uint256 public constant CIRCLE_COMPLETED_POINTS = 50;
    uint256 public constant ON_TIME_MULTIPLIER = 500;
    uint256 public constant MISSED_PAYMENT_PENALTY = 100;
    uint256 public constant AMOUNT_SAVED_DIVISOR = 1000; // Points per $1000 saved
    uint256 public constant ACCOUNT_AGE_MULTIPLIER = 5; // Points per month
    
    // ============ Events ============
    
    event ReputationUpdated(
        address indexed user,
        uint256 newScore,
        ReputationTier newTier
    );
    
    event CircleCompleted(address indexed user);
    event PaymentRecorded(address indexed user, bool onTime);
    event ContributionRecorded(address indexed user, uint256 amount);
    
    // ============ Modifiers ============
    
    modifier onlyAuthorized() {
        require(authorizedCallers[msg.sender], "Not authorized");
        _;
    }
    
    // ============ Constructor ============
    
    constructor() Ownable(msg.sender) {}
    
    // ============ Core Functions ============
    
    /**
     * @notice Initialize reputation for a new user
     * @param _user Address of the user
     */
    function initializeUser(address _user) external onlyAuthorized {
        if (userReputations[_user].accountCreated == 0) {
            userReputations[_user].accountCreated = block.timestamp;
            userReputations[_user].lastActive = block.timestamp;
        }
    }
    
    /**
     * @notice Record a contribution payment
     * @param _user Address of the user
     * @param _amount Amount contributed
     * @param _onTime Whether payment was on time
     */
    function recordContribution(
        address _user,
        uint256 _amount,
        bool _onTime
    ) external onlyAuthorized {
        UserReputation storage rep = userReputations[_user];
        
        rep.totalContributed += _amount;
        rep.lastActive = block.timestamp;
        
        if (_onTime) {
            rep.onTimePayments++;
        } else {
            rep.missedPayments++;
        }
        
        _updateReputationScore(_user);
        
        emit PaymentRecorded(_user, _onTime);
        emit ContributionRecorded(_user, _amount);
    }
    
    /**
     * @notice Record circle completion
     * @param _user Address of the user
     */
    function recordCircleCompletion(address _user) external onlyAuthorized {
        UserReputation storage rep = userReputations[_user];
        
        rep.circlesCompleted++;
        if (rep.circlesActive > 0) {
            rep.circlesActive--;
        }
        rep.lastActive = block.timestamp;
        
        _updateReputationScore(_user);
        
        emit CircleCompleted(_user);
    }
    
    /**
     * @notice Join a new circle
     * @param _user Address of the user
     */
    function recordCircleJoined(address _user) external onlyAuthorized {
        userReputations[_user].circlesActive++;
        userReputations[_user].lastActive = block.timestamp;
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Calculate and update reputation score
     * @param _user Address of the user
     */
    function _updateReputationScore(address _user) internal {
        UserReputation storage rep = userReputations[_user];
        
        // Base points from completed circles
        uint256 score = rep.circlesCompleted * CIRCLE_COMPLETED_POINTS;
        
        // On-time rate multiplier (0-500 points)
        uint256 totalPayments = rep.onTimePayments + rep.missedPayments;
        if (totalPayments > 0) {
            uint256 onTimeRate = (rep.onTimePayments * 100) / totalPayments;
            score += (onTimeRate * ON_TIME_MULTIPLIER) / 100;
        }
        
        // Penalty for missed payments
        score = score > (rep.missedPayments * MISSED_PAYMENT_PENALTY) 
            ? score - (rep.missedPayments * MISSED_PAYMENT_PENALTY)
            : 0;
        
        // Bonus for amount saved (10 points per $1000)
        score += (rep.totalContributed / (AMOUNT_SAVED_DIVISOR * 1 ether)) * 10;
        
        // Bonus for account age (5 points per month)
        uint256 accountAgeMonths = (block.timestamp - rep.accountCreated) / 30 days;
        score += accountAgeMonths * ACCOUNT_AGE_MULTIPLIER;
        
        // Cap at 1000 for standard tier system
        if (score > 1000) {
            score = 1000;
        }
        
        rep.reputationScore = score;
        rep.tier = _calculateTier(score);
        
        emit ReputationUpdated(_user, score, rep.tier);
    }
    
    /**
     * @notice Calculate reputation tier based on score
     * @param _score Reputation score
     * @return tier Reputation tier
     */
    function _calculateTier(uint256 _score) internal pure returns (ReputationTier) {
        if (_score >= 1000) return ReputationTier.DIAMOND;
        if (_score >= 750) return ReputationTier.PLATINUM;
        if (_score >= 500) return ReputationTier.GOLD;
        if (_score >= 250) return ReputationTier.SILVER;
        return ReputationTier.BRONZE;
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get user reputation details
     * @param _user Address of the user
     */
    function getUserReputation(address _user) external view returns (
        uint256 score,
        ReputationTier tier,
        uint256 circlesCompleted,
        uint256 circlesActive,
        uint256 totalContributed,
        uint256 onTimeRate
    ) {
        UserReputation storage rep = userReputations[_user];
        
        uint256 totalPayments = rep.onTimePayments + rep.missedPayments;
        uint256 rate = totalPayments > 0 
            ? (rep.onTimePayments * 100) / totalPayments 
            : 100;
        
        return (
            rep.reputationScore,
            rep.tier,
            rep.circlesCompleted,
            rep.circlesActive,
            rep.totalContributed,
            rate
        );
    }
    
    /**
     * @notice Get reputation score for external use (lending protocols, etc.)
     * @param _user Address of the user
     * @return score Reputation score (0-1000)
     */
    function getReputationScore(address _user) external view returns (uint256) {
        return userReputations[_user].reputationScore;
    }
    
    /**
     * @notice Check if user meets minimum reputation requirement
     * @param _user Address of the user
     * @param _minScore Minimum required score
     */
    function meetsRequirement(address _user, uint256 _minScore) external view returns (bool) {
        return userReputations[_user].reputationScore >= _minScore;
    }
    
    /**
     * @notice Get tier name as string
     * @param _tier Reputation tier enum
     */
    function getTierName(ReputationTier _tier) external pure returns (string memory) {
        if (_tier == ReputationTier.DIAMOND) return "Diamond";
        if (_tier == ReputationTier.PLATINUM) return "Platinum";
        if (_tier == ReputationTier.GOLD) return "Gold";
        if (_tier == ReputationTier.SILVER) return "Silver";
        return "Bronze";
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Authorize a contract to update reputation
     * @param _caller Address to authorize (e.g., ChainCircle contract)
     */
    function authorizeCaller(address _caller) external onlyOwner {
        require(_caller != address(0), "Invalid address");
        authorizedCallers[_caller] = true;
    }
    
    /**
     * @notice Revoke authorization
     * @param _caller Address to revoke
     */
    function revokeCaller(address _caller) external onlyOwner {
        authorizedCallers[_caller] = false;
    }
}
