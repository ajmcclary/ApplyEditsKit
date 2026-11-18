import XCTest
@testable import ApplyEditsKit

/// Pins `OptimalLineFinderUtility`'s results. The utility scores candidate
/// lines on concurrent workers, so these tests also guard that the result is
/// the same on every run (ties resolve to the lowest line, not to whichever
/// worker finishes first).
final class OptimalLineFinderUtilityTests: XCTestCase {
	private func change(startLine: Int, _ lines: [String]) -> FileChange {
		FileChange(
			startLine: startLine,
			description: "",
			diffChunk: DiffChunk(lines: lines.map(DiffLine.init(content:)), startLine: startLine)
		)
	}

	private let file = [
		"import Foundation",   // 0
		"",                    // 1
		"struct Account {",    // 2
		"    var id: Int",     // 3
		"}",                   // 4
		"",                    // 5
		"func total() -> Int {", // 6
		"    return 42",       // 7
		"}",                   // 8
	]

	func testFindsTheDriftedLineWithinTheSearchRadius() {
		let drifted = change(startLine: 4, [" func total() -> Int {", "-    return 42", "+    return 43"])
		XCTAssertEqual(OptimalLineFinderUtility.findOptimalLine(for: drifted, in: file, around: 4), 6)
	}

	func testKeepsTheStartLineWhenItsFirstContextLineAlreadyMatches() {
		let exact = change(startLine: 6, [" func total() -> Int {", "-    return 42", "+    return 43"])
		XCTAssertEqual(OptimalLineFinderUtility.findOptimalLine(for: exact, in: file, around: 6), 6)
	}

	func testTiesResolveToTheLowestLineOnEveryRun() {
		// "}" scores identically at lines 4 and 8; neither is the start line.
		let ambiguous = change(startLine: 6, [" }"])
		for _ in 0..<200 {
			XCTAssertEqual(OptimalLineFinderUtility.findOptimalLine(for: ambiguous, in: file, around: 6), 4)
		}
	}

	func testParallelVariantReturnsOneLinePerChangeMatchingTheSerialResult() {
		let changes = (0..<64).map { index in
			index.isMultiple(of: 2)
				? change(startLine: 4, [" func total() -> Int {"])
				: change(startLine: 1, [" struct Account {"])
		}
		for _ in 0..<20 {
			let lines = OptimalLineFinderUtility.findOptimalLinesInParallel(for: changes, in: file)
			XCTAssertEqual(lines.count, changes.count)
			for change in changes {
				XCTAssertEqual(
					lines[change.id],
					OptimalLineFinderUtility.findOptimalLine(for: change, in: file, around: change.startLine)
				)
			}
		}
		XCTAssertEqual(OptimalLineFinderUtility.findOptimalLinesInParallel(for: changes, in: file)[changes[0].id], 6)
		XCTAssertEqual(OptimalLineFinderUtility.findOptimalLinesInParallel(for: changes, in: file)[changes[1].id], 2)
	}

	func testParallelVariantHandlesNoChanges() {
		XCTAssertEqual(OptimalLineFinderUtility.findOptimalLinesInParallel(for: [], in: file), [:])
	}
}
