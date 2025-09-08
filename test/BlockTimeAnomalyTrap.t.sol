// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BlockTimeAnomalyTrap} from "../src/BlockTimeAnomalyTrap.sol";

/**
 * @title Tests for Block Time Anomaly Trap
 * @notice Comprehensive test suite for the timing anomaly detection logic
 */
contract BlockTimeAnomalyTrapTest is Test {
    BlockTimeAnomalyTrap public trap;

    function setUp() public {
        trap = new BlockTimeAnomalyTrap();
    }

    function testCollectReturnsValidData() public {
        bytes memory data = trap.collect();
        (uint256 version, uint256 timestamp, uint256 blockNum, string memory discord) = 
            abi.decode(data, (uint256, uint256, uint256, string));

        assertEq(version, 1);
        assertTrue(timestamp > 0);
        assertTrue(blockNum > 0);
        assertTrue(bytes(discord).length > 0);
    }

    function testShouldNotRespondWithInsufficientData() public {
        bytes[] memory data = new bytes[](2); // Only 2 blocks, need 3
        data[0] = abi.encode(1, block.timestamp, block.number, "test");
        data[1] = abi.encode(1, block.timestamp - 15, block.number - 1, "test");

        (bool shouldRespond,) = trap.shouldRespond(data);
        assertFalse(shouldRespond);
    }

    function testDetectsTooSlowAnomaly() public {
        bytes[] memory data = new bytes[](3);

        uint256 baseTime = 1000000;
        uint256 baseBlock = 100;

        // Create data with 70-second interval (too slow)
        data[0] = abi.encode(1, baseTime, baseBlock, "test");
        data[1] = abi.encode(1, baseTime - 70, baseBlock - 1, "test"); // 70s gap
        data[2] = abi.encode(1, baseTime - 85, baseBlock - 2, "test"); // 15s gap

        (bool shouldRespond, bytes memory responseData) = trap.shouldRespond(data);

        assertTrue(shouldRespond);
        (string memory discord, uint256 blockNumber, uint256 interval1, uint256 interval2, uint8 anomalyType,) = 
            abi.decode(responseData, (string, uint256, uint256, uint256, uint8, uint256));

        assertEq(discord, "test");
        assertEq(blockNumber, baseBlock);
        assertEq(interval1, 70);
        assertEq(interval2, 15);
        assertEq(anomalyType, 1); // TooSlow
    }

    function testDetectsTooFastAnomaly() public {
        bytes[] memory data = new bytes[](3);

        uint256 baseTime = 1000000;
        uint256 baseBlock = 100;

        // Create data with 1-second interval (too fast)
        data[0] = abi.encode(1, baseTime, baseBlock, "test");
        data[1] = abi.encode(1, baseTime - 1, baseBlock - 1, "test"); // 1s gap
        data[2] = abi.encode(1, baseTime - 13, baseBlock - 2, "test"); // 12s gap

        (bool shouldRespond, bytes memory responseData) = trap.shouldRespond(data);

        assertTrue(shouldRespond);
        (, , , , uint8 anomalyType,) = abi.decode(responseData, (string, uint256, uint256, uint256, uint8, uint256));
        assertEq(anomalyType, 2); // TooFast
    }

    function testDetectsHighVarianceAnomaly() public {
        bytes[] memory data = new bytes[](3);

        uint256 baseTime = 1000000;
        uint256 baseBlock = 100;

        // Create data with high variance (45s vs 5s = 40s variance > 25s threshold)
        data[0] = abi.encode(1, baseTime, baseBlock, "test");
        data[1] = abi.encode(1, baseTime - 45, baseBlock - 1, "test"); // 45s gap
        data[2] = abi.encode(1, baseTime - 50, baseBlock - 2, "test"); // 5s gap

        (bool shouldRespond, bytes memory responseData) = trap.shouldRespond(data);

        assertTrue(shouldRespond);
        (, , , , uint8 anomalyType,) = abi.decode(responseData, (string, uint256, uint256, uint256, uint8, uint256));
        assertEq(anomalyType, 3); // HighVariance
    }

    function testDetectsStalledAnomaly() public {
        bytes[] memory data = new bytes[](3);

        uint256 baseTime = 1000000;
        uint256 baseBlock = 100;

        // Create data with stalling (both intervals > 36s = 3x normal)
        data[0] = abi.encode(1, baseTime, baseBlock, "test");
        data[1] = abi.encode(1, baseTime - 40, baseBlock - 1, "test"); // 40s gap
        data[2] = abi.encode(1, baseTime - 78, baseBlock - 2, "test"); // 38s gap

        (bool shouldRespond, bytes memory responseData) = trap.shouldRespond(data);

        assertTrue(shouldRespond);
        (, , , , uint8 anomalyType,) = abi.decode(responseData, (string, uint256, uint256, uint256, uint8, uint256));
        assertEq(anomalyType, 4); // Stalled
    }

    function testNormalTimingDoesNotTrigger() public {
        bytes[] memory data = new bytes[](3);

        uint256 baseTime = 1000000;
        uint256 baseBlock = 100;

        // Create normal timing data (12s and 13s intervals)
        data[0] = abi.encode(1, baseTime, baseBlock, "test");
        data[1] = abi.encode(1, baseTime - 12, baseBlock - 1, "test");
        data[2] = abi.encode(1, baseTime - 25, baseBlock - 2, "test");

        (bool shouldRespond,) = trap.shouldRespond(data);
        assertFalse(shouldRespond);
    }

    function testRejectsInvalidVersions() public {
        bytes[] memory data = new bytes[](3);

        // Invalid version in first data point
        data[0] = abi.encode(2, block.timestamp, block.number, "test"); // Wrong version
        data[1] = abi.encode(1, block.timestamp - 15, block.number - 1, "test");
        data[2] = abi.encode(1, block.timestamp - 30, block.number - 2, "test");

        (bool shouldRespond,) = trap.shouldRespond(data);
        assertFalse(shouldRespond);
    }

    function testRejectsEmptyDiscordName() public {
        bytes[] memory data = new bytes[](3);

        data[0] = abi.encode(1, block.timestamp, block.number, ""); // Empty Discord name
        data[1] = abi.encode(1, block.timestamp - 15, block.number - 1, "test");
        data[2] = abi.encode(1, block.timestamp - 30, block.number - 2, "test");

        (bool shouldRespond,) = trap.shouldRespond(data);
        assertFalse(shouldRespond);
    }

    function testRejectsIncorrectBlockOrder() public {
        bytes[] memory data = new bytes[](3);

        uint256 baseTime = 1000000;
        uint256 baseBlock = 100;

        // Blocks not in descending order
        data[0] = abi.encode(1, baseTime, baseBlock, "test");
        data[1] = abi.encode(1, baseTime - 15, baseBlock + 1, "test"); // Wrong order
        data[2] = abi.encode(1, baseTime - 30, baseBlock - 1, "test");

        (bool shouldRespond,) = trap.shouldRespond(data);
        assertFalse(shouldRespond);
    }

    function testGetConfigReturnsCorrectValues() public {
        (uint256 normalTime, uint256 maxTime, uint256 minTime, uint256 varianceThreshold) = trap.getConfig();

        assertEq(normalTime, 12);
        assertEq(maxTime, 60);
        assertEq(minTime, 2);
        assertEq(varianceThreshold, 25);
    }

    function testGetAnomalyDescriptions() public {
        assertEq(trap.getAnomalyDescription(1), "Block production too slow - potential network issues");
        assertEq(trap.getAnomalyDescription(2), "Block production too fast - possible timestamp manipulation");
        assertEq(trap.getAnomalyDescription(3), "High timing variance - network instability detected");
        assertEq(trap.getAnomalyDescription(4), "Network stalling - consensus issues detected");
        assertEq(trap.getAnomalyDescription(0), "No anomaly detected");
    }

    function testGetDiscordName() public {
        string memory discordName = trap.getDiscordName();
        assertTrue(bytes(discordName).length > 0);
    }
}
