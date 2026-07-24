//
//  DiffChunkTests.swift
//  RepoPromptTests
//
//  Created by RepoPrompt on 2025-07-03.
//

import XCTest
@testable import ApplyEditsKit

class DiffChunkTests: XCTestCase {
    
    // MARK: - Line Count Tests
    
    func testOldLineCountWithOnlyAdditions() {
        // Given
        let chunk = DiffChunk(
            lines: [
                DiffLine(content: "+Added line 1"),
                DiffLine(content: "+Added line 2"),
                DiffLine(content: "+Added line 3")
            ],
            startLine: 1
        )
        
        // When
        let oldCount = chunk.oldLineCount
        let newCount = chunk.newLineCount
        
        // Then
        XCTAssertEqual(oldCount, 0) // No lines in old version
        XCTAssertEqual(newCount, 3) // 3 lines in new version
    }
    
    func testOldLineCountWithOnlyRemovals() {
        // Given
        let chunk = DiffChunk(
            lines: [
                DiffLine(content: "-Removed line 1"),
                DiffLine(content: "-Removed line 2")
            ],
            startLine: 5
        )
        
        // When
        let oldCount = chunk.oldLineCount
        let newCount = chunk.newLineCount
        
        // Then
        XCTAssertEqual(oldCount, 2) // 2 lines in old version
        XCTAssertEqual(newCount, 0) // No lines in new version
    }
    
    func testOldLineCountWithMixedChanges() {
        // Given
        let chunk = DiffChunk(
            lines: [
                DiffLine(content: " Context line 1"),
                DiffLine(content: "-Old line"),
                DiffLine(content: "+New line"),
                DiffLine(content: " Context line 2"),
                DiffLine(content: "+Another new line"),
                DiffLine(content: " Context line 3")
            ],
            startLine: 10
        )
        
        // When
        let oldCount = chunk.oldLineCount
        let newCount = chunk.newLineCount
        
        // Then
        XCTAssertEqual(oldCount, 4) // 3 context + 1 removal
        XCTAssertEqual(newCount, 5) // 3 context + 2 additions
    }
    
    func testOldLineCountWithOnlyContext() {
        // Given
        let chunk = DiffChunk(
            lines: [
                DiffLine(content: " Line 1"),
                DiffLine(content: " Line 2"),
                DiffLine(content: " Line 3")
            ],
            startLine: 1
        )
        
        // When
        let oldCount = chunk.oldLineCount
        let newCount = chunk.newLineCount
        
        // Then
        XCTAssertEqual(oldCount, 3) // All context lines appear in old
        XCTAssertEqual(newCount, 3) // All context lines appear in new
    }
    
    // MARK: - Line Count Difference Tests
    
    func testLineCountDifferenceWithAdditions() {
        // Given
        let chunk = DiffChunk(
            lines: [
                DiffLine(content: " Context"),
                DiffLine(content: "+Added 1"),
                DiffLine(content: "+Added 2"),
                DiffLine(content: " Context")
            ],
            startLine: 1
        )
        
        // When
        let difference = chunk.lineCountDifference()
        
        // Then
        XCTAssertEqual(difference, 2) // +2 lines added
    }
    
    func testLineCountDifferenceWithRemovals() {
        // Given
        let chunk = DiffChunk(
            lines: [
                DiffLine(content: " Context"),
                DiffLine(content: "-Removed 1"),
                DiffLine(content: "-Removed 2"),
                DiffLine(content: "-Removed 3"),
                DiffLine(content: " Context")
            ],
            startLine: 1
        )
        
        // When
        let difference = chunk.lineCountDifference()
        
        // Then
        XCTAssertEqual(difference, -3) // -3 lines removed
    }
    
    func testLineCountDifferenceWithReplacement() {
        // Given
        let chunk = DiffChunk(
            lines: [
                DiffLine(content: "-Old implementation"),
                DiffLine(content: "-    with two lines"),
                DiffLine(content: "+New implementation"),
                DiffLine(content: "+    with"),
                DiffLine(content: "+    three"),
                DiffLine(content: "+    lines")
            ],
            startLine: 5
        )
        
        // When
        let difference = chunk.lineCountDifference()
        
        // Then
        XCTAssertEqual(difference, 2) // -2 removed, +4 added = +2 net
    }
    
    // MARK: - Edge Cases
    
    func testEmptyChunk() {
        // Given
        let chunk = DiffChunk(lines: [], startLine: 1)
        
        // When
        let oldCount = chunk.oldLineCount
        let newCount = chunk.newLineCount
        let difference = chunk.lineCountDifference()
        
        // Then
        XCTAssertEqual(oldCount, 0)
        XCTAssertEqual(newCount, 0)
        XCTAssertEqual(difference, 0)
    }
    
    func testChunkWithSpecialCharacters() {
        // Given
        let chunk = DiffChunk(
            lines: [
                DiffLine(content: " let regex = /^\\d+$/"),
                DiffLine(content: "-let special = \"<>&'\""),
                DiffLine(content: "+let special = \"<>&'\\\"escaped\\\"\"")
            ],
            startLine: 42
        )
        
        // When
        let oldCount = chunk.oldLineCount
        let newCount = chunk.newLineCount
        
        // Then
        XCTAssertEqual(oldCount, 2) // 1 context + 1 removal
        XCTAssertEqual(newCount, 2) // 1 context + 1 addition
        XCTAssertEqual(chunk.lineCountDifference(), 0) // Replacement, no net change
    }
}

// MARK: - Performance Tests

class UnifiedDiffPerformanceTests: XCTestCase {
    
    func testPerformanceWithLargeFile() {
        // Given
        let lineCount = 10000
        let oldLines = (1...lineCount).map { "Line \($0)" }
        var newLines = oldLines
        
        // Modify every 100th line
        for i in stride(from: 99, to: lineCount, by: 100) {
            newLines[i] = "Modified Line \(i + 1)"
        }
        
        // When/Then
        measure {
            let expectation = self.expectation(description: "Diff generation")
            
            Task {
                _ = try? await UnifiedDiffGenerator.build(
                    oldLines: oldLines,
                    newLines: newLines,
                    filePath: "large-file.txt"
                )
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
    
    func testPerformanceWithManySmallChanges() {
        // Given
        let oldLines = Array(repeating: "Original line", count: 1000)
        var newLines = oldLines
        
        // Change every other line
        for i in stride(from: 0, to: 1000, by: 2) {
            newLines[i] = "Changed line"
        }
        
        // When/Then
        measure {
            let expectation = self.expectation(description: "Diff generation")
            
            Task {
                _ = try? await UnifiedDiffGenerator.build(
                    oldLines: oldLines,
                    newLines: newLines,
                    filePath: "many-changes.txt"
                )
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
}
