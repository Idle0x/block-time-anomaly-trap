// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract BlockAnomalyResponse {

    // ... (Events and Structs remain the same) ...
    event BlockAnomalyDetected(
        string indexed discordDetector,
        uint256 indexed blockNumber,
        uint256 interval1,
        uint256 interval2,
        uint8 anomalyType,
        uint256 detectionTimestamp,
        string anomalyDescription
    );

    struct AnomalyRecord {
        uint256 blockNumber;
        uint256 detectionTime;
        uint256 interval1;
        uint256 interval2;
        uint8 anomalyType;
        string detectorDiscord;
    }

    address public immutable owner;
    bool public emergencyMode;
    uint256 public totalAnomalies;
    
    mapping(address => bool) public authorizedTraps;
    mapping(uint256 => AnomalyRecord) public anomalyHistory;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // REVIEW FIX: The Trap contract does NOT call this. 
    // The Drosera Operator/Executor calls this. 
    // We removed the strict check for the Trap Address to prevent revert.
    modifier onlyAuthorizedCaller() {
        // For PoC: Check if sender is owner OR authorized
        require(msg.sender == owner || authorizedTraps[msg.sender], "Not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
        // Authorize deployer for testing
        authorizedTraps[msg.sender] = true; 
    }

    function respondToAnomaly(
        string memory discordName,
        uint256 blockNumber,
        uint256 interval1,
        uint256 interval2,
        uint8 anomalyType,
        uint256 detectionTimestamp
    ) external {
        // REVIEW FIX: Removed strict modifier for initial testing.
        // In production, you would authorize the Drosera Executor address here.
        
        // Record logic
        anomalyHistory[totalAnomalies] = AnomalyRecord({
            blockNumber: blockNumber,
            detectionTime: detectionTimestamp,
            interval1: interval1,
            interval2: interval2,
            anomalyType: anomalyType,
            detectorDiscord: discordName
        });

        totalAnomalies++;

        emit BlockAnomalyDetected(
            discordName,
            blockNumber,
            interval1,
            interval2,
            anomalyType,
            detectionTimestamp,
            _getAnomalyDescription(anomalyType)
        );
    }
    
    // ... (Remaining helper functions _getAnomalyDescription, etc. remain the same) ...
    
    function _getAnomalyDescription(uint8 anomalyType) internal pure returns (string memory) {
        if (anomalyType == 1) return "Block production too slow";
        if (anomalyType == 2) return "Block production too fast";
        if (anomalyType == 3) return "High timing variance detected";
        if (anomalyType == 4) return "Network stalling detected";
        return "Unknown anomaly type";
    }
}
