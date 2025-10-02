// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @title ChainCircle
 * @notice Main contract for cross-chain savings circles on Push Chain
 * @dev Implements rotating savings and credit associations (ROSCAs) with yield generation
 */
contract ChainCircle is ReentrancyGuard, Ownable {
    
    // ============ Structs ============
    
    struct Circle {
        bytes32 circleId;
        address creator;
        uint256 contributionAmount;     // Amount per contribution in wei
        uint256 contributionFrequency;  // In seconds (e.g., 30 days)
        uint256 duration;               // Number of contribution periods
        uint256 createdAt;
        uint256 startedAt;
        CircleStatus status;
        GoalType goalType;
        address[] members;
        uint256 currentRound;           // Current payout round
        uint256 totalPooled;            // Total funds in circle
        uint256 interestEarned;         // Total interest earned
    }
    
    struct Contribution {
        address member;
        uint256 amount;
        uint256 timestamp;
        uint256 round;
    }
    
    struct Payout {
        address recipient;
        uint256 amount;
        uint256 interestBonus;
        uint256 timestamp;
        uint256 round;
    }
    
    // ============ Enums ============
    
    enum CircleStatus {
        PENDING,    // Created but not started
        ACTIVE,     // Currently running
        COMPLETED,  // Successfully finished
        CANCELLED   // Cancelled due to issues
    }
    
    enum GoalType {
        HOME,
        EDUCATION,
        BUSINESS,
        EMERGENCY,
        TRAVEL,
        OTHER
    }
    
    // ============ State Variables ============
    
    mapping(bytes32 => Circle) public circles;
    mapping(bytes32 => mapping(address => bool)) public circleMemberships;
    mapping(bytes32 => mapping(uint256 => mapping(address => bool))) public hasContributed;
    mapping(bytes32 => mapping(address => bool)) public hasReceivedPayout;
    mapping(bytes32 => Contribution[]) public contributions;
    mapping(bytes32 => Payout[]) public payouts;
    mapping(bytes32 => uint256) public circleBalances;
    
    // Protocol settings
    uint256 public constant PROTOCOL_FEE_PERCENT = 1; // 1% creation fee
    uint256 public constant INTEREST_PROTOCOL_SHARE = 20; // 20% of interest
    uint256 public constant SIMULATED_APR = 4; // 4% annual for demo
    uint256 public constant MAX_MEMBERS = 12;
    uint256 public constant MIN_MEMBERS = 3;
    
    address public protocolTreasury;
    uint256 public totalProtocolFees;
    
    // ============ Events ============
    
    event CircleCreated(
        bytes32 indexed circleId,
        address indexed creator,
        uint256 contributionAmount,
        uint256 duration,
        GoalType goalType
    );
    
    event MemberJoined(bytes32 indexed circleId, address indexed member);
    
    event CircleStarted(bytes32 indexed circleId, uint256 startedAt);
    
    event ContributionMade(
        bytes32 indexed circleId,
        address indexed member,
        uint256 amount,
        uint256 round
    );
    
    event PayoutProcessed(
        bytes32 indexed circleId,
        address indexed recipient,
        uint256 amount,
        uint256 interestBonus,
        uint256 round
    );
    
    event CircleCompleted(bytes32 indexed circleId, uint256 completedAt);
    
    // ============ Constructor ============
    
    constructor(address _protocolTreasury) Ownable(msg.sender) {
        require(_protocolTreasury != address(0), "Invalid treasury");
        protocolTreasury = _protocolTreasury;
    }
    
    // ============ Core Functions ============
    
    /**
     * @notice Create a new savings circle
     * @param _contributionAmount Amount each member contributes per period
     * @param _contributionFrequency Time between contributions (in seconds)
     * @param _duration Number of contribution periods
     * @param _goalType Type of savings goal
     */
    function createCircle(
        uint256 _contributionAmount,
        uint256 _contributionFrequency,
        uint256 _duration,
        GoalType _goalType
    ) external returns (bytes32) {
        require(_contributionAmount > 0, "Invalid amount");
        require(_duration >= MIN_MEMBERS && _duration <= MAX_MEMBERS, "Invalid duration");
        
        bytes32 circleId = keccak256(
            abi.encodePacked(msg.sender, block.timestamp, _contributionAmount)
        );
        
        Circle storage circle = circles[circleId];
        circle.circleId = circleId;
        circle.creator = msg.sender;
        circle.contributionAmount = _contributionAmount;
        circle.contributionFrequency = _contributionFrequency;
        circle.duration = _duration;
        circle.createdAt = block.timestamp;
        circle.status = CircleStatus.PENDING;
        circle.goalType = _goalType;
        circle.currentRound = 0;
        
        // Creator automatically joins
        circle.members.push(msg.sender);
        circleMemberships[circleId][msg.sender] = true;
        
        emit CircleCreated(circleId, msg.sender, _contributionAmount, _duration, _goalType);
        emit MemberJoined(circleId, msg.sender);
        
        return circleId;
    }
    
    /**
     * @notice Join an existing circle
     * @param _circleId ID of the circle to join
     */
    function joinCircle(bytes32 _circleId) external payable nonReentrant {
        Circle storage circle = circles[_circleId];
        
        require(circle.creator != address(0), "Circle does not exist");
        require(circle.status == CircleStatus.PENDING, "Circle already started");
        require(!circleMemberships[_circleId][msg.sender], "Already a member");
        require(circle.members.length < MAX_MEMBERS, "Circle is full");
        require(msg.value >= circle.contributionAmount, "Insufficient contribution");
        
        // Add member
        circle.members.push(msg.sender);
        circleMemberships[_circleId][msg.sender] = true;
        
        // Record first contribution
        circle.totalPooled += msg.value;
        circleBalances[_circleId] += msg.value;
        hasContributed[_circleId][0][msg.sender] = true;
        
        contributions[_circleId].push(Contribution({
            member: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp,
            round: 0
        }));
        
        emit MemberJoined(_circleId, msg.sender);
        emit ContributionMade(_circleId, msg.sender, msg.value, 0);
        
        // Auto-start circle if minimum members reached
        if (circle.members.length >= MIN_MEMBERS) {
            _startCircle(_circleId);
        }
    }
    
    /**
     * @notice Make a contribution for the current round
     * @param _circleId ID of the circle
     */
    function contribute(bytes32 _circleId) external payable nonReentrant {
        Circle storage circle = circles[_circleId];
        
        require(circle.status == CircleStatus.ACTIVE, "Circle not active");
        require(circleMemberships[_circleId][msg.sender], "Not a member");
        require(!hasContributed[_circleId][circle.currentRound][msg.sender], "Already contributed this round");
        require(msg.value >= circle.contributionAmount, "Insufficient amount");
        
        // Record contribution
        circle.totalPooled += msg.value;
        circleBalances[_circleId] += msg.value;
        hasContributed[_circleId][circle.currentRound][msg.sender] = true;
        
        contributions[_circleId].push(Contribution({
            member: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp,
            round: circle.currentRound
        }));
        
        emit ContributionMade(_circleId, msg.sender, msg.value, circle.currentRound);
    }
    
    /**
     * @notice Process payout for the current round
     * @param _circleId ID of the circle
     * @param _recipient Address to receive payout (must be next in rotation)
     */
    function processPayout(bytes32 _circleId, address _recipient) external nonReentrant {
        Circle storage circle = circles[_circleId];
        
        require(circle.status == CircleStatus.ACTIVE, "Circle not active");
        require(circleMemberships[_circleId][_recipient], "Recipient not a member");
        require(!hasReceivedPayout[_circleId][_recipient], "Already received payout");
        
        // Check if all contributions are in for this round
        uint256 contributionsCount = 0;
        for (uint256 i = 0; i < circle.members.length; i++) {
            if (hasContributed[_circleId][circle.currentRound][circle.members[i]]) {
                contributionsCount++;
            }
        }
        require(contributionsCount == circle.members.length, "Not all members contributed");
        
        // Calculate payout amount
        uint256 roundPool = circle.contributionAmount * circle.members.length;
        
        // Calculate simulated interest
        uint256 interest = _calculateInterest(roundPool, circle.contributionFrequency);
        circle.interestEarned += interest;
        
        // Split interest: 80% to members, 20% to protocol
        uint256 protocolInterest = (interest * INTEREST_PROTOCOL_SHARE) / 100;
        uint256 memberInterest = interest - protocolInterest;
        
        uint256 payoutAmount = roundPool + memberInterest;
        
        require(circleBalances[_circleId] >= payoutAmount, "Insufficient balance");
        
        // Update state
        circleBalances[_circleId] -= payoutAmount;
        hasReceivedPayout[_circleId][_recipient] = true;
        totalProtocolFees += protocolInterest;
        
        // Record payout
        payouts[_circleId].push(Payout({
            recipient: _recipient,
            amount: roundPool,
            interestBonus: memberInterest,
            timestamp: block.timestamp,
            round: circle.currentRound
        }));
        
        // Transfer funds
        (bool success, ) = _recipient.call{value: payoutAmount}("");
        require(success, "Transfer failed");
        
        emit PayoutProcessed(_circleId, _recipient, roundPool, memberInterest, circle.currentRound);
        
        // Move to next round or complete circle
        circle.currentRound++;
        if (circle.currentRound >= circle.duration) {
            circle.status = CircleStatus.COMPLETED;
            emit CircleCompleted(_circleId, block.timestamp);
        }
    }
    
    // ============ Internal Functions ============
    
    function _startCircle(bytes32 _circleId) internal {
        Circle storage circle = circles[_circleId];
        circle.status = CircleStatus.ACTIVE;
        circle.startedAt = block.timestamp;
        
        // Calculate and collect protocol fee
        uint256 totalPool = circle.contributionAmount * circle.members.length * circle.duration;
        uint256 protocolFee = (totalPool * PROTOCOL_FEE_PERCENT) / 100;
        totalProtocolFees += protocolFee;
        
        emit CircleStarted(_circleId, block.timestamp);
    }
    
    function _calculateInterest(uint256 _amount, uint256 _duration) internal pure returns (uint256) {
        // Simple interest calculation: (amount * APR * time) / (365 days * 100)
        // Simulated APR for demo purposes
        return (_amount * SIMULATED_APR * _duration) / (365 days * 100);
    }
    
    // ============ View Functions ============
    
    function getCircle(bytes32 _circleId) external view returns (
        address creator,
        uint256 contributionAmount,
        uint256 duration,
        CircleStatus status,
        address[] memory members,
        uint256 currentRound,
        uint256 totalPooled
    ) {
        Circle storage circle = circles[_circleId];
        return (
            circle.creator,
            circle.contributionAmount,
            circle.duration,
            circle.status,
            circle.members,
            circle.currentRound,
            circle.totalPooled
        );
    }
    
    function getCircleMembers(bytes32 _circleId) external view returns (address[] memory) {
        return circles[_circleId].members;
    }
    
    function getContributions(bytes32 _circleId) external view returns (Contribution[] memory) {
        return contributions[_circleId];
    }
    
    function getPayouts(bytes32 _circleId) external view returns (Payout[] memory) {
        return payouts[_circleId];
    }
    
    function hasUserContributed(bytes32 _circleId, uint256 _round, address _user) 
        external 
        view 
        returns (bool) 
    {
        return hasContributed[_circleId][_round][_user];
    }
    
    // ============ Admin Functions ============
    
    function withdrawProtocolFees() external onlyOwner {
        uint256 amount = totalProtocolFees;
        totalProtocolFees = 0;
        
        (bool success, ) = protocolTreasury.call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    function updateProtocolTreasury(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), "Invalid address");
        protocolTreasury = _newTreasury;
    }
    
    // ============ Receive Function ============
    
    receive() external payable {}
}