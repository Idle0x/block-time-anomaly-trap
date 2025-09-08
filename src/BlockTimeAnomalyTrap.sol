// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

/**
 * @title Block Time Anomaly Detector
 * @author idle0x
 * @notice Detects unusual block timing patterns that could indicate network issues
 * @dev Monitors block timestamps and intervals for anomalous patterns across multiple blocks
 * 
 * This trap provides infrastructure-level security monitoring by analyzing:
 * - Block production intervals
 * - Timing variance patterns  
 * - Network stalling detection
 * - Potential timestamp manipulation
 */
contract BlockTimeAnomalyTrap is ITrap {

    // ============= CONFIGURATION =============

    /// @notice Discord username for identification - REPLACE WITH YOUR DISCORD
    string constant DISCORD_NAME = "idle0x";

    /// @notice Expected normal block time in seconds (Ethereum ~12s)
    uint256 constant NORMAL_BLOCK_TIME = 12;

    /// @notice Maximum acceptable block time before considering anomalous
    uint256 constant MAX_BLOCK_TIME = 60;

    /// @notice Minimum acceptable block time before considering anomalous  
    uint256 constant MIN_BLOCK_TIME = 2;

    /// @notice Variance threshold - difference between intervals to flag
    uint256 constant VARIANCE_THRESHOLD = 25;

    /// @notice Multiplier for stalling detection (3x normal = stalling)
    uint256 constant STALL_MULTIPLIER = 3;

    // ============= ENUMS =============

    /// @notice Types of timing anomalies that can be detected
    enum AnomalyType {
        None,           // No anomaly detected
        TooSlow,        // Block interval exceeds maximum threshold
        TooFast,        // Block interval below minimum threshold  
        HighVariance,   // Large variance between consecutive intervals
        Stalled         // Network showing signs of stalling
    }

    // ============= MAIN FUNCTIONS =============

    /**
     * @notice Collects current block timing data for analysis
     * @return Encoded data containing version, timestamp, block number, and Discord name
     */
    function collect() external view returns (bytes memory) {
        uint256 version = 1; // Required by Drosera protocol
        uint256 currentTimestamp = block.timestamp;
        uint256 currentBlock = block.number;

        return abi.encode(
            version,
            currentTimestamp,
            currentBlock,
            DISCORD_NAME
        );
    }

    /**
     * @notice Analyzes collected timing data to determine if response needed
     * @param data Array of collected data from recent blocks (requires minimum 3 blocks)
     * @return shouldTrigger True if timing anomaly detected
     * @return responseData Encoded response data for the response contract
     */
    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
        // Require minimum 3 data points for pattern analysis
        if (data.length < 3) {
            return (false, bytes(""));
        }

        // Decode the three most recent blocks (data[0] = newest)
        (
            uint256 version1,
            uint256 time1,
            uint256 block1,
            string memory discordName
        ) = abi.decode(data[0], (uint256, uint256, uint256, string));

        (
            uint256 version2,
            uint256 time2,
            uint256 block2,

        ) = abi.decode(data[1], (uint256, uint256, uint256, string));

        (
            uint256 version3,
            uint256 time3,
            uint256 block3,

        ) = abi.decode(data[2], (uint256, uint256, uint256, string));

        // Validate data integrity
        if (!_isValidData(version1, version2, version3, discordName, block1, block2, block3)) {
            return (false, bytes(""));
        }

        // Calculate block intervals
        uint256 interval1 = time1 - time2; // Most recent interval
        uint256 interval2 = time2 - time3; // Previous interval

        // Detect anomaly type
        AnomalyType anomalyType = _detectAnomalyType(interval1, interval2);

        // If anomaly detected, prepare response data
        if (anomalyType != AnomalyType.None) {
            bytes memory responseData = abi.encode(
                discordName,
                block1,
                interval1,
                interval2,
                uint8(anomalyType),
                block.timestamp
            );
            return (true, responseData);
        }

        return (false, bytes(""));
    }

    // ============= INTERNAL FUNCTIONS =============

    /**
     * @notice Validates the integrity of collected data
     * @param version1 Version from newest block
     * @param version2 Version from middle block  
     * @param version3 Version from oldest block
     * @param discordName Discord username from data
     * @param block1 Newest block number
     * @param block2 Middle block number
     * @param block3 Oldest block number
     * @return isValid True if data passes validation checks
     */
    function _isValidData(
        uint256 version1,
        uint256 version2, 
        uint256 version3,
        string memory discordName,
        uint256 block1,
        uint256 block2,
        uint256 block3
    ) internal pure returns (bool isValid) {
        // Check versions match expected
        if (version1 != 1 || version2 != 1 || version3 != 1) {
            return false;
        }

        // Check Discord name exists
        if (bytes(discordName).length == 0) {
            return false;
        }

        // Ensure blocks are in correct chronological order (newest first)
        if (block1 <= block2 || block2 <= block3) {
            return false;
        }

        // Ensure blocks are consecutive or nearly consecutive
        if (block1 - block3 > 10) {
            return false; // Too much gap between blocks
        }

        return true;
    }

    /**
     * @notice Core anomaly detection logic analyzing timing patterns
     * @param interval1 Most recent block interval in seconds
     * @param interval2 Previous block interval in seconds
     * @return anomalyType The type of anomaly detected
     */
    function _detectAnomalyType(
        uint256 interval1, 
        uint256 interval2
    ) internal pure returns (AnomalyType) {

        // Pattern 1: Extremely slow blocks (network congestion/issues)
        if (interval1 >= MAX_BLOCK_TIME || interval2 >= MAX_BLOCK_TIME) {
            return AnomalyType.TooSlow;
        }

        // Pattern 2: Extremely fast blocks (timestamp manipulation/bugs)
        if (interval1 <= MIN_BLOCK_TIME || interval2 <= MIN_BLOCK_TIME) {
            return AnomalyType.TooFast;
        }

        // Pattern 3: High variance between consecutive intervals (instability)
        uint256 variance = interval1 > interval2 ? interval1 - interval2 : interval2 - interval1;
        if (variance >= VARIANCE_THRESHOLD) {
            return AnomalyType.HighVariance;
        }

        // Pattern 4: Network stalling (both intervals significantly above normal)
        uint256 stallThreshold = NORMAL_BLOCK_TIME * STALL_MULTIPLIER;
        if (interval1 >= stallThreshold && interval2 >= stallThreshold) {
            return AnomalyType.Stalled;
        }

        return AnomalyType.None;
    }

    // ============= VIEW FUNCTIONS =============

    /**
     * @notice Get current configuration parameters
     * @return normalTime Expected normal block time
     * @return maxTime Maximum acceptable block time
     * @return minTime Minimum acceptable block time
     * @return varianceThreshold Variance threshold for detection
     */
    function getConfig() external pure returns (
        uint256 normalTime,
        uint256 maxTime, 
        uint256 minTime,
        uint256 varianceThreshold
    ) {
        return (NORMAL_BLOCK_TIME, MAX_BLOCK_TIME, MIN_BLOCK_TIME, VARIANCE_THRESHOLD);
    }

    /**
     * @notice Get human-readable description for anomaly type
     * @param anomalyType The anomaly type to describe
     * @return description Human-readable anomaly description
     */
    function getAnomalyDescription(uint8 anomalyType) external pure returns (string memory description) {
        if (anomalyType == 1) return "Block production too slow - potential network issues";
        if (anomalyType == 2) return "Block production too fast - possible timestamp manipulation";
        if (anomalyType == 3) return "High timing variance - network instability detected";
        if (anomalyType == 4) return "Network stalling - consensus issues detected";
        return "No anomaly detected";
    }

    /**
     * @notice Get the Discord name configured for this trap
     * @return discordName The Discord username
     */
    function getDiscordName() external pure returns (string memory discordName) {
        return DISCORD_NAME;
    }
}
