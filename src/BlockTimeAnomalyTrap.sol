// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

contract BlockTimeAnomalyTrap is ITrap {

    // ============= CONFIGURATION =============
    string constant DISCORD_NAME = "idle0x";
    uint256 constant NORMAL_BLOCK_TIME = 12;
    uint256 constant MAX_BLOCK_TIME = 60;
    uint256 constant MIN_BLOCK_TIME = 2;
    uint256 constant VARIANCE_THRESHOLD = 25;
    uint256 constant STALL_MULTIPLIER = 3;

    // ============= ENUMS =============
    enum AnomalyType {
        None,           // 0
        TooSlow,        // 1
        TooFast,        // 2
        HighVariance,   // 3
        Stalled         // 4
    }

    // ============= MAIN FUNCTIONS =============

    function collect() external view returns (bytes memory) {
        // Collects current block data
        return abi.encode(
            uint256(1), // Version
            block.timestamp,
            block.number,
            DISCORD_NAME
        );
    }

    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
        // 1. Safety Check: Ensure we have 3 blocks and no empty blobs
        if (data.length < 3 || data[0].length == 0 || data[1].length == 0 || data[2].length == 0) {
            return (false, bytes(""));
        }

        // 2. Decode Data (Fixed Syntax)
        (uint256 version1, uint256 time1, uint256 block1, string memory discordName) = 
            abi.decode(data[0], (uint256, uint256, uint256, string));

        (uint256 version2, uint256 time2, uint256 block2, ) = 
            abi.decode(data[1], (uint256, uint256, uint256, string));

        (uint256 version3, uint256 time3, uint256 block3, ) = 
            abi.decode(data[2], (uint256, uint256, uint256, string));

        // 3. Monotonic Time Check (Prevent Underflow)
        // Time must move forward: time1 (newest) > time2 > time3
        if (time1 <= time2 || time2 <= time3) {
            return (false, bytes(""));
        }

        // 4. Validate Data Integrity
        if (!_isValidData(version1, version2, version3, discordName, block1, block2, block3)) {
            return (false, bytes(""));
        }

        // 5. Calculate Intervals
        uint256 interval1 = time1 - time2; 
        uint256 interval2 = time2 - time3; 

        // 6. Detect Anomaly
        AnomalyType anomalyType = _detectAnomalyType(interval1, interval2);

        if (anomalyType != AnomalyType.None) {
            // FIXED: Used `time1` instead of `block.timestamp` to keep function PURE
            bytes memory responseData = abi.encode(
                discordName,
                block1,
                interval1,
                interval2,
                uint8(anomalyType),
                time1 
            );
            return (true, responseData);
        }

        return (false, bytes(""));
    }

    // ============= INTERNAL FUNCTIONS =============

    function _isValidData(
        uint256 v1, uint256 v2, uint256 v3,
        string memory discordName,
        uint256 b1, uint256 b2, uint256 b3
    ) internal pure returns (bool) {
        if (v1 != 1 || v2 != 1 || v3 != 1) return false;
        if (bytes(discordName).length == 0) return false;
        // Blocks must be ordered (Newest > Middle > Oldest)
        if (b1 <= b2 || b2 <= b3) return false;
        if (b1 - b3 > 10) return false; // Gap too large
        return true;
    }

    function _detectAnomalyType(uint256 i1, uint256 i2) internal pure returns (AnomalyType) {
        // Priority 1: Stalling (Most Critical)
        // Moved this UP per review to ensure Stalling isn't masked by Variance
        uint256 stallThreshold = NORMAL_BLOCK_TIME * STALL_MULTIPLIER; // 36s
        if (i1 >= stallThreshold && i2 >= stallThreshold) {
            return AnomalyType.Stalled;
        }

        // Priority 2: Too Slow
        if (i1 >= MAX_BLOCK_TIME || i2 >= MAX_BLOCK_TIME) {
            return AnomalyType.TooSlow;
        }

        // Priority 3: Too Fast
        if (i1 <= MIN_BLOCK_TIME || i2 <= MIN_BLOCK_TIME) {
            return AnomalyType.TooFast;
        }

        // Priority 4: High Variance
        uint256 variance = i1 > i2 ? i1 - i2 : i2 - i1;
        if (variance >= VARIANCE_THRESHOLD) {
            return AnomalyType.HighVariance;
        }

        return AnomalyType.None;
    }
}
