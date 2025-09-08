// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Block Anomaly Response Contract
 * @author idle0x
 * @notice Handles automated responses when block timing anomalies are detected
 * @dev Called by Drosera operators when BlockTimeAnomalyTrap triggers
 */
contract BlockAnomalyResponse {

    // ============= EVENTS =============

    /// @notice Emitted when a block timing anomaly is detected and responded to
    event BlockAnomalyDetected(
        string indexed discordDetector,
        uint256 indexed blockNumber,
        uint256 interval1,
        uint256 interval2,
        uint8 anomalyType,
        uint256 detectionTimestamp,
        string anomalyDescription
    );

    /// @notice Emitted when emergency mode status changes
    event EmergencyModeChanged(
        bool isEmergencyMode,
        string reason,
        uint256 timestamp,
        address changedBy
    );

    /// @notice Emitted when trap authorization changes
    event TrapAuthorizationChanged(
        address indexed trapAddress,
        bool authorized,
        uint256 timestamp
    );

    // ============= STRUCTS =============

    /// @notice Record of a detected anomaly
    struct AnomalyRecord {
        uint256 blockNumber;        // Block where anomaly occurred
        uint256 detectionTime;     // When anomaly was detected
        uint256 interval1;         // Most recent block interval
        uint256 interval2;         // Previous block interval
        uint8 anomalyType;         // Type of anomaly (1-4)
        string detectorDiscord;    // Who detected it
    }

    // ============= STATE VARIABLES =============

    /// @notice Contract owner (deployer)
    address public immutable owner;

    /// @notice Current emergency mode status
    bool public emergencyMode;

    /// @notice Total number of anomalies detected
    uint256 public totalAnomalies;

    /// @notice Block number of most recent anomaly
    uint256 public lastAnomalyBlock;

    /// @notice Timestamp of most recent anomaly
    uint256 public lastAnomalyTime;

    /// @notice Mapping of authorized trap contracts
    mapping(address => bool) public authorizedTraps;

    /// @notice Historical record of all anomalies
    mapping(uint256 => AnomalyRecord) public anomalyHistory;

    // ============= MODIFIERS =============

    modifier onlyOwner() {
        require(msg.sender == owner, "BlockAnomalyResponse: Not owner");
        _;
    }

    modifier onlyAuthorizedTrap() {
        require(authorizedTraps[msg.sender], "BlockAnomalyResponse: Not authorized trap");
        _;
    }

    // ============= CONSTRUCTOR =============

    constructor() {
        owner = msg.sender;
        emergencyMode = false;
        totalAnomalies = 0;
    }

    // ============= MAIN FUNCTIONS =============

    /**
     * @notice Main response function called by Drosera when anomaly detected
     * @param discordName Discord username of the detector
     * @param blockNumber Block where anomaly was detected
     * @param interval1 Most recent block interval in seconds
     * @param interval2 Previous block interval in seconds
     * @param anomalyType Type of anomaly detected (1=TooSlow, 2=TooFast, 3=HighVariance, 4=Stalled)
     * @param detectionTimestamp When the anomaly was detected
     */
    function respondToAnomaly(
        string memory discordName,
        uint256 blockNumber,
        uint256 interval1,
        uint256 interval2,
        uint8 anomalyType,
        uint256 detectionTimestamp
    ) external onlyAuthorizedTrap {

        // Validate input parameters
        require(bytes(discordName).length > 0, "Discord name required");
        require(anomalyType >= 1 && anomalyType <= 4, "Invalid anomaly type");
        require(blockNumber > 0, "Invalid block number");

        // Record the anomaly in history
        anomalyHistory[totalAnomalies] = AnomalyRecord({
            blockNumber: blockNumber,
            detectionTime: detectionTimestamp,
            interval1: interval1,
            interval2: interval2,
            anomalyType: anomalyType,
            detectorDiscord: discordName
        });

        // Update state
        lastAnomalyBlock = blockNumber;
        lastAnomalyTime = detectionTimestamp;
        totalAnomalies++;

        // Get human-readable description
        string memory description = _getAnomalyDescription(anomalyType);

        // Emit comprehensive event
        emit BlockAnomalyDetected(
            discordName,
            blockNumber,
            interval1,
            interval2,
            anomalyType,
            detectionTimestamp,
            description
        );

        // Check if this anomaly warrants emergency mode
        bool shouldEnterEmergency = _shouldEnterEmergencyMode(anomalyType, interval1, interval2);

        if (shouldEnterEmergency && !emergencyMode) {
            _setEmergencyMode(true, description);
        }
    }

    /**
     * @notice Authorize a trap contract to trigger responses
     * @param trapAddress Address of the trap contract to authorize
     */
    function authorizeTrap(address trapAddress) external onlyOwner {
        require(trapAddress != address(0), "Invalid trap address");

        authorizedTraps[trapAddress] = true;

        emit TrapAuthorizationChanged(trapAddress, true, block.timestamp);
    }

    /**
     * @notice Revoke authorization for a trap contract
     * @param trapAddress Address of the trap contract to deauthorize
     */
    function deauthorizeTrap(address trapAddress) external onlyOwner {
        authorizedTraps[trapAddress] = false;

        emit TrapAuthorizationChanged(trapAddress, false, block.timestamp);
    }

    /**
     * @notice Manually control emergency mode (owner only)
     * @param _emergencyMode New emergency mode status
     * @param reason Reason for the change
     */
    function setEmergencyMode(bool _emergencyMode, string memory reason) external onlyOwner {
        _setEmergencyMode(_emergencyMode, reason);
    }

    // ============= VIEW FUNCTIONS =============

    /**
     * @notice Check if the network is currently considered healthy
     * @return healthy True if no emergency mode and no recent severe anomalies
     */
    function isNetworkHealthy() external view returns (bool healthy) {
        if (emergencyMode) {
            return false;
        }

        // Consider healthy if no anomalies in last 50 blocks (~10 minutes)
        if (totalAnomalies > 0 && (block.number - lastAnomalyBlock) < 50) {
            return false;
        }

        return true;
    }

    /**
     * @notice Get recent anomaly history
     * @param count Number of recent anomalies to return (max 20)
     * @return anomalies Array of recent anomaly records
     */
    function getRecentAnomalies(uint256 count) external view returns (AnomalyRecord[] memory anomalies) {
        if (count > 20) count = 20; // Limit to prevent gas issues
        if (count > totalAnomalies) count = totalAnomalies;

        anomalies = new AnomalyRecord[](count);

        for (uint256 i = 0; i < count; i++) {
            anomalies[i] = anomalyHistory[totalAnomalies - 1 - i];
        }

        return anomalies;
    }

    /**
     * @notice Get statistics about detected anomalies
     * @return total Total anomalies detected
     * @return lastBlock Block of most recent anomaly
     * @return lastTime Timestamp of most recent anomaly  
     * @return inEmergency Current emergency mode status
     */
    function getStats() external view returns (
        uint256 total,
        uint256 lastBlock,
        uint256 lastTime,
        bool inEmergency
    ) {
        return (totalAnomalies, lastAnomalyBlock, lastAnomalyTime, emergencyMode);
    }

    // ============= INTERNAL HELPER FUNCTIONS =============

    /**
     * @notice Determine if detected anomaly warrants emergency mode
     * @param anomalyType Type of anomaly detected
     * @param interval1 Most recent block interval
     * @param interval2 Previous block interval
     * @return shouldEnter True if emergency mode should be activated
     */
    function _shouldEnterEmergencyMode(
        uint8 anomalyType,
        uint256 interval1,
        uint256 interval2
    ) internal pure returns (bool shouldEnter) {
        // Emergency triggers for severe conditions
        if (anomalyType == 1) { // TooSlow
            // Emergency if any interval >120 seconds (very severe delay)
            return (interval1 >= 120 || interval2 >= 120);
        }

        if (anomalyType == 2) { // TooFast  
            // Emergency if any interval ≤1 second (likely manipulation)
            return (interval1 <= 1 || interval2 <= 1);
        }

        if (anomalyType == 4) { // Stalled
            // Always emergency for stalling
            return true;
        }

        // High variance alone doesn't trigger emergency
        return false;
    }

    /**
     * @notice Internal function to set emergency mode
     * @param _emergencyMode New emergency mode status
     * @param reason Reason for the change
     */
    function _setEmergencyMode(bool _emergencyMode, string memory reason) internal {
        if (emergencyMode != _emergencyMode) {
            emergencyMode = _emergencyMode;
            emit EmergencyModeChanged(_emergencyMode, reason, block.timestamp, msg.sender);
        }
    }

    /**
     * @notice Get human-readable description for anomaly type
     * @param anomalyType Numeric anomaly type
     * @return description Human-readable description
     */
    function _getAnomalyDescription(uint8 anomalyType) internal pure returns (string memory description) {
        if (anomalyType == 1) return "Block production too slow";
        if (anomalyType == 2) return "Block production too fast";
        if (anomalyType == 3) return "High timing variance detected";
        if (anomalyType == 4) return "Network stalling detected";
        return "Unknown anomaly type";
    }
}
