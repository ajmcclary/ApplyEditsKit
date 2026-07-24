//
//  UnifiedDiffGeneratorTests.swift
//  RepoPromptTests
//
//  Created by RepoPrompt on 2025-07-03.
//

import XCTest
@testable import ApplyEditsKit

class UnifiedDiffGeneratorTests: XCTestCase {
    
    // MARK: - File Creation Tests
    
    func testGenerateDiffForFileCreation() async throws {
        // Given
        let newLines = [
            "import Foundation",
            "",
            "struct MyStruct {",
            "    let name: String",
            "}"
        ]
        let filePath = "Sources/MyStruct.swift"
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: nil,
            newLines: newLines,
            filePath: filePath
        )
        
        // Then
        XCTAssertTrue(diff.contains("--- /dev/null"))
        XCTAssertTrue(diff.contains("+++ b/Sources/MyStruct.swift"))
        
        // The diff for a new file should contain no body lines or hunk headers
        let bodyLines = diff.components(separatedBy: .newlines).dropFirst(2)
        XCTAssertFalse(bodyLines.contains { $0.hasPrefix("+") || $0.hasPrefix("@@") })
    }
    
    // MARK: - File Deletion Tests
    
    func testGenerateDiffForFileDeletion() async throws {
        // Given
        let oldLines = [
            "class OldClass {",
            "    var value: Int = 0",
            "}"
        ]
        let filePath = "Sources/OldClass.swift"
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: nil,
            filePath: filePath
        )
        
        // Then
        XCTAssertTrue(diff.contains("--- a/Sources/OldClass.swift"))
        XCTAssertTrue(diff.contains("+++ /dev/null"))
        
        // The diff for a deleted file should contain no body lines or hunk headers
        let bodyLines = diff.components(separatedBy: .newlines).dropFirst(2)
        XCTAssertFalse(bodyLines.contains { $0.hasPrefix("-") || $0.hasPrefix("@@") })
    }
    
    // MARK: - File Modification Tests
    
    func testGenerateDiffForSimpleModification() async throws {
        // Given
        let oldLines = [
            "struct Person {",
            "    let name: String",
            "    let age: Int",
            "}"
        ]
        let newLines = [
            "struct Person {",
            "    let name: String",
            "    let age: Int",
            "    let email: String",
            "}"
        ]
        let filePath = "Models/Person.swift"
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: filePath
        )
        
        // Then
        XCTAssertTrue(diff.contains("--- a/Models/Person.swift"))
        XCTAssertTrue(diff.contains("+++ b/Models/Person.swift"))
        XCTAssertTrue(diff.contains(" struct Person {"))
        XCTAssertTrue(diff.contains("     let name: String"))
        XCTAssertTrue(diff.contains("     let age: Int"))
        XCTAssertTrue(diff.contains("+    let email: String"))
        XCTAssertTrue(diff.contains(" }"))
    }
    
    func testGenerateDiffForMultipleChanges() async throws {
        // Given
        let oldLines = [
            "import UIKit",
            "",
            "class ViewController: UIViewController {",
            "    override func viewDidLoad() {",
            "        super.viewDidLoad()",
            "        setupUI()",
            "    }",
            "",
            "    func setupUI() {",
            "        // TODO: Setup UI",
            "    }",
            "}"
        ]
        let newLines = [
            "import UIKit",
            "import Combine",
            "",
            "class ViewController: UIViewController {",
            "    private var cancellables = Set<AnyCancellable>()",
            "",
            "    override func viewDidLoad() {",
            "        super.viewDidLoad()",
            "        setupUI()",
            "        bindViewModel()",
            "    }",
            "",
            "    func setupUI() {",
            "        view.backgroundColor = .systemBackground",
            "    }",
            "",
            "    func bindViewModel() {",
            "        // Bind to view model",
            "    }",
            "}"
        ]
        let filePath = "ViewControllers/ViewController.swift"
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: filePath
        )
        
        // Then
        XCTAssertTrue(diff.contains("--- a/ViewControllers/ViewController.swift"))
        XCTAssertTrue(diff.contains("+++ b/ViewControllers/ViewController.swift"))
        XCTAssertTrue(diff.contains(" import UIKit"))
        XCTAssertTrue(diff.contains("+import Combine"))
        XCTAssertTrue(diff.contains("+    private var cancellables = Set<AnyCancellable>()"))
        XCTAssertTrue(diff.contains("+        bindViewModel()"))
        XCTAssertTrue(diff.contains("-        // TODO: Setup UI"))
        XCTAssertTrue(diff.contains("+        view.backgroundColor = .systemBackground"))
        XCTAssertTrue(diff.contains("+    func bindViewModel() {"))
    }
    
    // MARK: - Empty Content Tests
    
    func testGenerateDiffForEmptyFiles() async throws {
        // Given
        let emptyLines: [String]? = []
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: emptyLines,
            newLines: emptyLines,
            filePath: "empty.txt"
        )
        
        // Then
        // No diff output for identical empty files
        XCTAssertTrue(diff.isEmpty)
    }
    
    func testGenerateDiffFromEmptyToContent() async throws {
        // Given
        let oldLines: [String] = []
        let newLines = ["Hello, World!"]
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: "hello.txt"
        )
        
        // Then
        XCTAssertTrue(diff.contains("--- a/hello.txt"))
        XCTAssertTrue(diff.contains("+++ b/hello.txt"))
        XCTAssertTrue(diff.contains("+Hello, World!"))
    }
    
    // MARK: - Context Tests
    
    func testGenerateDiffWithCustomContext() async throws {
        // Given - Test with a single change in the middle of a file
        let oldLines = ["Line 1", "Line 2", "Line 3", "Line 4", "Line 5", 
                        "Line 6", "Line 7", "Line 8", "Line 9", "Line 10"]
        var newLines = oldLines
        newLines[4] = "Modified Line 5"  // Change line 5 (index 4)
        
        // When
        let diffWithContext1 = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: "test.txt",
            context: 1
        )
        
        let diffWithContext3 = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: "test.txt",
            context: 3
        )
        
        // Then - Both should contain the change
        XCTAssertTrue(diffWithContext1.contains("-Line 5"))
        XCTAssertTrue(diffWithContext1.contains("+Modified Line 5"))
        XCTAssertTrue(diffWithContext3.contains("-Line 5"))
        XCTAssertTrue(diffWithContext3.contains("+Modified Line 5"))
        
        
        // Context=1 should show 1 line of context on each side
        XCTAssertTrue(diffWithContext1.contains(" Line 4"))  // 1 before
        XCTAssertTrue(diffWithContext1.contains(" Line 6"))  // 1 after
        
        // Context=3 should show 3 lines of context on each side
        XCTAssertTrue(diffWithContext3.contains(" Line 2"))  // 3 before
        XCTAssertTrue(diffWithContext3.contains(" Line 3"))
        XCTAssertTrue(diffWithContext3.contains(" Line 4"))
        XCTAssertTrue(diffWithContext3.contains(" Line 6"))  // 3 after
        XCTAssertTrue(diffWithContext3.contains(" Line 7"))
        XCTAssertTrue(diffWithContext3.contains(" Line 8"))
        
        // Verify proper hunk headers are generated
        XCTAssertTrue(diffWithContext1.contains("@@"))
        XCTAssertTrue(diffWithContext3.contains("@@"))
        
        // The diff should be well-formed
        let lines1 = diffWithContext1.components(separatedBy: .newlines)
        let lines3 = diffWithContext3.components(separatedBy: .newlines)
        XCTAssertTrue(lines1.count >= 5)  // At least header + hunk header + 3 content lines
        XCTAssertTrue(lines3.count >= 9)  // At least header + hunk header + 7 content lines
    }
    
    // MARK: - Special Characters Tests
    
    func testGenerateDiffWithSpecialCharacters() async throws {
        // Given
        let oldLines = [
            "let regex = /^\\d+$/",
            "let special = \"<>&'\""
        ]
        let newLines = [
            "let regex = /^\\w+$/",
            "let special = \"<>&'\\\"escaped\\\"\""
        ]
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: "special.swift"
        )
        
        // Then
        XCTAssertTrue(diff.contains("-let regex = /^\\d+$/"))
        XCTAssertTrue(diff.contains("+let regex = /^\\w+$/"))
        XCTAssertTrue(diff.contains("-let special = \"<>&'\""))
        XCTAssertTrue(diff.contains("+let special = \"<>&'\\\"escaped\\\"\""))
    }
    
    // MARK: - Edge Cases
    
    func testGenerateDiffWithNoChanges() async throws {
        // Given
        let lines = ["Same content", "No changes"]
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: lines,
            newLines: lines,
            filePath: "unchanged.txt"
        )
        
        // Then
        XCTAssertTrue(diff.isEmpty)
    }
    
    func testGenerateDiffWithBothNil() async throws {
        // Given/When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: nil,
            newLines: nil,
            filePath: "nonexistent.txt"
        )
        
        // Then
        XCTAssertEqual(diff, "")
    }

    
    func testGenerateDiffSummaryForCreatedFile() async throws {
        // Given
        let newContent = "struct NewStruct {\n    let value: Int\n}"
        let filePath = "NewFile.swift"
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: nil,
            newLines: newContent.components(separatedBy: .newlines),
            filePath: filePath
        )
        
        // Then
        XCTAssertTrue(diff.contains("--- /dev/null"))
        XCTAssertTrue(diff.contains("+++ b/NewFile.swift"))
        
        // Ensure no body lines or hunk headers are present
        let bodyLines = diff.components(separatedBy: .newlines).dropFirst(2)
        XCTAssertFalse(bodyLines.contains { $0.hasPrefix("+") || $0.hasPrefix("@@") })
    }
    
    func testGenerateDiffSummaryForModifiedFile() async throws {
        // Given
        let originalContent = "class OldClass {\n    var value: Int = 0\n}"
        let modifiedContent = "class OldClass {\n    var value: Int = 42\n}"
        let filePath = "ExistingFile.swift"
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: originalContent.components(separatedBy: .newlines),
            newLines: modifiedContent.components(separatedBy: .newlines),
            filePath: filePath
        )
        
        // Then
        XCTAssertTrue(diff.contains("--- a/ExistingFile.swift"))
        XCTAssertTrue(diff.contains("+++ b/ExistingFile.swift"))
        XCTAssertTrue(diff.contains("-    var value: Int = 0"))
        XCTAssertTrue(diff.contains("+    var value: Int = 42"))
        
        // Verify context lines are included
        XCTAssertTrue(diff.contains(" class OldClass {"))
        XCTAssertTrue(diff.contains(" }"))
    }
    
    func testGenerateDiffSummaryForComplexChanges() async throws {
        // Given
        let originalContent = [
            "import Foundation",
            "",
            "class MyClass {",
            "    func oldMethod() {",
            "        print(\"old\")",
            "    }",
            "}"
        ].joined(separator: "\n")
        
        let modifiedContent = [
            "import Foundation",
            "import UIKit",
            "",
            "class MyClass {",
            "    var newProperty: String = \"\"",
            "    ",
            "    func oldMethod() {",
            "        print(\"modified\")",
            "    }",
            "    ",
            "    func newMethod() {",
            "        print(\"new\")",
            "    }",
            "}"
        ].joined(separator: "\n")
        
        let filePath = "MyClass.swift"
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: originalContent.components(separatedBy: .newlines),
            newLines: modifiedContent.components(separatedBy: .newlines),
            filePath: filePath
        )
        
        // Then
        XCTAssertTrue(diff.contains("+import UIKit"))
        XCTAssertTrue(diff.contains("+    var newProperty: String = \"\""))
        XCTAssertTrue(diff.contains("-        print(\"old\")"))
        XCTAssertTrue(diff.contains("+        print(\"modified\")"))
        XCTAssertTrue(diff.contains("+    func newMethod() {"))
        XCTAssertTrue(diff.contains("+        print(\"new\")"))
        
        // Verify multiple hunks are created for non-adjacent changes
        let hunkCount = diff.components(separatedBy: .newlines).filter { $0.hasPrefix("@@") }.count
        XCTAssertGreaterThan(hunkCount, 0)
    }
	
    func testSplitContentPreservingLineEndingsWithUnixEndings() {
        // Given
        let content = "Line 1\nLine 2\nLine 3"
        
        // When
        let (lines, lineEnding) = String.splitContentPreservingLineEndings(content)
        
        // Then
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "Line 1")
        XCTAssertEqual(lines[1], "Line 2")
        XCTAssertEqual(lines[2], "Line 3")
        XCTAssertEqual(lineEnding, "\n")
    }
    
    func testSplitContentPreservingLineEndingsWithWindowsEndings() {
        // Given
        let content = "Line 1\r\nLine 2\r\nLine 3"
        
        // When
        let (lines, lineEnding) = String.splitContentPreservingLineEndings(content)
        
        // Then
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "Line 1")
        XCTAssertEqual(lines[1], "Line 2")
        XCTAssertEqual(lines[2], "Line 3")
        XCTAssertEqual(lineEnding, "\r\n")
    }
    
    func testSplitContentPreservingLineEndingsWithEmptyLines() {
        // Given
        let content = "Line 1\n\nLine 3\n"
        
        // When
        let (lines, _) = String.splitContentPreservingLineEndings(content)
        
        // Then
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "Line 1")
        XCTAssertEqual(lines[1], "")
        XCTAssertEqual(lines[2], "Line 3")
    }
    
    func testSplitContentPreservingLineEndingsWithMixedEndings() {
        // Given
        let content = "Unix\nWindows\r\nClassic Mac\rUnix Again\n"
        
        // When
        let (lines, lineEnding) = String.splitContentPreservingLineEndings(content)
        
        // Then
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0], "Unix")
        XCTAssertEqual(lines[1], "Windows")
        XCTAssertEqual(lines[2], "Classic Mac")
        XCTAssertEqual(lines[3], "Unix Again")
        // Should detect the first line ending type
        XCTAssertEqual(lineEnding, "\n")
    }

    /// A large unchanged gap (> context*2) should result in separate hunks.
    func testHunkSplittingWithLargeGap() async throws {
        // Given - Create changes with a clear large gap
        let oldLines = Array(1...50).map { "Line \($0)" }
        var newLines = oldLines
        newLines[4]  = "Modified Line 5"   // change at line 5
        newLines[44] = "Modified Line 45"  // change at line 45 (gap of 40 lines)
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: "LargeGapFile.txt"
        )
        
        // Then – we expect TWO hunks for these far-apart changes
        let hunkCount = diff.components(separatedBy: .newlines).filter { $0.hasPrefix("@@") }.count
        XCTAssertEqual(hunkCount, 2, "Diff should be split into two hunks for a large gap")
        XCTAssertTrue(diff.contains("+Modified Line 5"))
        XCTAssertTrue(diff.contains("+Modified Line 45"))
    }
    
    /// Two small, close changes with minimal gap naturally form a single hunk.
    func testHunkMergingForSmallGap() async throws {
        // Given - Changes very close together
        let oldLines = Array(1...20).map { "Line \($0)" }
        var newLines = oldLines
        newLines[9] = "Modified Line 10"   // first change at line 10
        newLines[11] = "Modified Line 12"  // second change at line 12 (gap of 1 line)
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: "SmallGapFile.txt"
        )
        
        // Then – changes only 1 line apart naturally form a single hunk
        // With context=3, the context around these changes overlaps
        let hunkCount = diff.components(separatedBy: .newlines).filter { $0.hasPrefix("@@") }.count
        XCTAssertEqual(hunkCount, 1, "Very close changes naturally form a single hunk")
        XCTAssertTrue(diff.contains("+Modified Line 10"))
        XCTAssertTrue(diff.contains("+Modified Line 12"))
    }
    
    /// Verify diff correctness when a modification occurs at the very first line
    /// (tests behaviour with an empty leading context buffer).
    func testModificationAtFileStart() async throws {
        // Given
        let oldLines = ["Second line", "Third line"]
        let newLines = ["First line inserted", "Second line", "Third line"]
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: "StartChange.txt"
        )
        
        // Then
        XCTAssertTrue(diff.contains("--- a/StartChange.txt"))
        XCTAssertTrue(diff.contains("+++ b/StartChange.txt"))
        XCTAssertTrue(diff.contains("+First line inserted"))
        
        // Should have exactly one hunk
        let hunkCount = diff.components(separatedBy: .newlines).filter { $0.hasPrefix("@@") }.count
        XCTAssertEqual(hunkCount, 1)
    }
 
    
    /// Multiple scattered single-line edits should produce separate hunks.
    func testScatteredSingleLineChanges() async throws {
        // Given - Three changes far apart to ensure separate hunks
        let oldLines = Array(1...200).map { "Line \($0)" }
        var newLines = oldLines
        newLines[9]  = "Changed Line 10"    // change at line 10
        newLines[99] = "Changed Line 100"   // change at line 100 (90 lines apart)
        newLines[189] = "Changed Line 190"  // change at line 190 (90 lines apart)
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: "Scattered.txt"
        )
        
        // Then - Expect 3 separate hunks for these distant changes
        let hunkCount = diff.components(separatedBy: .newlines).filter { $0.hasPrefix("@@") }.count
        XCTAssertEqual(hunkCount, 3, "Each distant change should create its own hunk")
        XCTAssertTrue(diff.contains("+Changed Line 10"))
        XCTAssertTrue(diff.contains("+Changed Line 100"))
        XCTAssertTrue(diff.contains("+Changed Line 190"))
    }
    
    /// A single change in a huge file should yield a very small patch.
    func testLargeFileMinimalChangesIsCompact() async throws {
        // Given
        let oldLines = Array(1...1000).map { "Line \($0)" }
        var newLines = oldLines
        newLines[499] = "Changed Line 500"
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: "HugeFile.txt"
        )
        
        // Then – expect a small diff with just the change and context
        // With context=3, we expect: 2 header lines + 1 hunk header + 8 content lines (3 before + 2 change lines + 3 after)
        let totalLines = diff.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        XCTAssertLessThanOrEqual(totalLines, 11, "Diff for a single change should remain very compact")
        XCTAssertTrue(diff.contains("+Changed Line 500"))
    }
    
    /// Neighbouring small edits naturally form a single hunk due to overlapping context.
    func testTinyHunkCoalescingForAdjacentChanges() async throws {
        // Given - Two changes with minimal gap
        let oldLines = Array(1...30).map { "Line \($0)" }
        var newLines = oldLines
        newLines[10] = "Changed Line 11"  // change at line 11
        newLines[12] = "Changed Line 13"  // change at line 13 (1 line gap)
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: "Adjacent.txt"
        )
        
        // Then – changes only 1 line apart naturally form a single hunk
        let hunkCount = diff.components(separatedBy: .newlines).filter { $0.hasPrefix("@@") }.count
        XCTAssertEqual(hunkCount, 1, "Adjacent changes naturally form a single hunk")
        XCTAssertTrue(diff.contains("+Changed Line 11"))
        XCTAssertTrue(diff.contains("+Changed Line 13"))
    }
    
    /// File creation and deletion should return headers only.
    func testCreateDeleteDiffHeadersOnly() async throws {
        // Create
        let createDiff = try await UnifiedDiffGenerator.build(
            oldLines: nil,
            newLines: ["Hello"],
            filePath: "Created.txt"
        )
        var bodyLines = createDiff.components(separatedBy: .newlines).dropFirst(2)
        XCTAssertFalse(bodyLines.contains { $0.hasPrefix("+") || $0.hasPrefix("@@") || $0.hasPrefix("-") })
        XCTAssertTrue(createDiff.contains("--- /dev/null"))
        XCTAssertTrue(createDiff.contains("+++ b/Created.txt"))
        
        // Delete
        let deleteDiff = try await UnifiedDiffGenerator.build(
            oldLines: ["Good-bye"],
            newLines: nil,
            filePath: "Deleted.txt"
        )
        bodyLines = deleteDiff.components(separatedBy: .newlines).dropFirst(2)
        XCTAssertFalse(bodyLines.contains { $0.hasPrefix("+") || $0.hasPrefix("@@") || $0.hasPrefix("-") })
        XCTAssertTrue(deleteDiff.contains("--- a/Deleted.txt"))
        XCTAssertTrue(deleteDiff.contains("+++ /dev/null"))
    }
    
    /// Edits at both the first and last line should produce separate hunks.
    func testChangesAtFileBoundaries() async throws {
        // Given
        let oldLines = Array(1...20).map { "Line \($0)" }
        var newLines = oldLines
        newLines[0]  = "Changed Line 1"
        newLines[19] = "Changed Line 20"
        
        // When
        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: "Boundary.txt"
        )
        
        // Then
        let hunkCount = diff.components(separatedBy: .newlines).filter { $0.hasPrefix("@@") }.count
        XCTAssertEqual(hunkCount, 2, "Boundary changes should result in two hunks")
        XCTAssertTrue(diff.contains("+Changed Line 1"))
        XCTAssertTrue(diff.contains("+Changed Line 20"))
    }
    
    // MARK: - Diff Chunk Stats Tests
    
    func testDiffStatsSingleReplacement() {
        // Given
        let oldLines = ["alpha", "beta", "gamma"]
        let newLines = ["alpha", "BETA", "gamma"]
        
        // When
        let chunks = UnifiedDiffGenerator.diffChunks(oldLines: oldLines, newLines: newLines)
        let stats = UnifiedDiffGenerator.stats(from: chunks)
        
        // Then
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(stats.linesChanged, 1)
        XCTAssertEqual(stats.chunks, 1)
    }
    
    func testDiffChunksBuildMatchesUnifiedDiff() async throws {
        // Given
        let oldLines = ["one", "two", "three", "four", "five"]
        let newLines = ["one", "TWO", "three", "four", "five", "six"]
        let filePath = "Samples/Example.txt"
        
        // When
        let chunks = UnifiedDiffGenerator.diffChunks(oldLines: oldLines, newLines: newLines)
        let diffFromChunks = UnifiedDiffGenerator.build(filePath: filePath, chunks: chunks)
        let diffFromLines = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: filePath
        )
        
        // Then
        XCTAssertEqual(diffFromChunks, diffFromLines)
        XCTAssertFalse(diffFromChunks.isEmpty)
    }
    
    func testDiffChunksEmptyForNoChange() {
        // Given
        let oldLines = ["same", "content"]
        let newLines = ["same", "content"]
        
        // When
        let chunks = UnifiedDiffGenerator.diffChunks(oldLines: oldLines, newLines: newLines)
        let stats = UnifiedDiffGenerator.stats(from: chunks)
        let diff = UnifiedDiffGenerator.build(filePath: "NoChange.txt", chunks: chunks)
        
        // Then
        XCTAssertTrue(chunks.isEmpty)
        XCTAssertEqual(stats.linesChanged, 0)
        XCTAssertEqual(stats.chunks, 0)
        XCTAssertTrue(diff.isEmpty)
    }

    func testBuildKeepsSingleHunkNewStartAtOriginalPositionWhenNetGrowthIsLarge() {
        let chunk = DiffChunk(
            lines: [
                DiffLine(content: "-This is a test edit file."),
                DiffLine(content: "-Created via RepoPrompt apply_edits."),
                DiffLine(content: "+# RepoPrompt MCP Tooling Test"),
                DiffLine(content: "+"),
                DiffLine(content: "+This file is used to validate larger edit operations."),
                DiffLine(content: "+"),
                DiffLine(content: "+## Details"),
                DiffLine(content: "+- Timestamp: March 16, 2026"),
                DiffLine(content: "+- Tool: RepoPrompt apply_edits"),
                DiffLine(content: "+- Operation: multi-line rewrite"),
                DiffLine(content: "+"),
                DiffLine(content: "+## Contents"),
                DiffLine(content: "+1. Created via MCP tools"),
                DiffLine(content: "+2. Verifies write capability"),
                DiffLine(content: "+3. Verified by readback"),
                DiffLine(content: "+"),
                DiffLine(content: "+## Notes"),
                DiffLine(content: "+This is only a tooling fixture.")
            ],
            startLine: 1
        )

        let diff = UnifiedDiffGenerator.build(filePath: "test_tool_edit.txt", chunks: [chunk])

        XCTAssertTrue(diff.contains("@@ -1,2 +1,16 @@"))
        XCTAssertFalse(diff.contains("@@ -1,2 +15,16 @@"))
    }

    func testBuildCarriesCumulativeDeltaForwardAcrossMultipleHunks() {
        let firstChunk = DiffChunk(
            lines: [
                DiffLine(content: " line1"),
                DiffLine(content: "-line2"),
                DiffLine(content: "+LINE2"),
                DiffLine(content: "+line2b")
            ],
            startLine: 1
        )
        let secondChunk = DiffChunk(
            lines: [
                DiffLine(content: " line12"),
                DiffLine(content: " line13"),
                DiffLine(content: "-line14"),
                DiffLine(content: "+LINE14")
            ],
            startLine: 12
        )

        let diff = UnifiedDiffGenerator.build(filePath: "file.swift", chunks: [firstChunk, secondChunk])

        XCTAssertTrue(diff.contains("@@ -1,2 +1,3 @@"))
        XCTAssertTrue(diff.contains("@@ -12,3 +13,3 @@"))
        XCTAssertFalse(diff.contains("@@ -12,3 +12,3 @@"))
    }

    func testBuildFromOldAndNewLinesIncludesLeadingContextInHunkStart() async throws {
        let oldLines = ["line1", "line2", "line3", "line4"]
        let newLines = ["line1", "line2", "LINE3", "line3b", "line4"]

        let diff = try await UnifiedDiffGenerator.build(
            oldLines: oldLines,
            newLines: newLines,
            filePath: "file.swift",
            context: 2
        )

        XCTAssertTrue(diff.contains("@@ -1,4 +1,5 @@"))
        XCTAssertFalse(diff.contains("@@ -3,2 +3,3 @@"))
    }
}
