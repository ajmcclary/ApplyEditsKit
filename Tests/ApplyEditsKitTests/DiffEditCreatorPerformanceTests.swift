//
//  DiffEditCreatorPerformanceTests.swift
//
//  The line diff behind every apply_edits result must stay linear-ish in
//  memory and time: rewrites that change every line and one-line edits in
//  very large files used to take tens of seconds and gigabytes.
//

import XCTest
@testable import ApplyEditsKit

final class DiffEditCreatorPerformanceTests: XCTestCase {
	func testMyersDiffOfDisjointLargeInputsIsCompleteAndFast() {
		let old = (0..<5_000).map { "a\($0)" }
		let new = (0..<5_000).map { "b\($0)" }
		let start = Date()
		let edits = DiffEditCreator.myersDiff(oldLines: old, newLines: new)
		XCTAssertLessThan(Date().timeIntervalSince(start), 5.0)
		XCTAssertEqual(edits.filter { $0.type == .deletion }.flatMap(\.lines), old)
		XCTAssertEqual(edits.filter { $0.type == .addition }.flatMap(\.lines), new)
		XCTAssertTrue(edits.allSatisfy { $0.lines.count == 1 })
	}

	func testMyersDiffKeepsCommonPrefixAndSuffixAsEqualLines() {
		let old = ["a", "b", "c", "d", "e"]
		let new = ["a", "b", "X", "d", "e"]
		let edits = DiffEditCreator.myersDiff(oldLines: old, newLines: new)
		XCTAssertEqual(edits.map(\.type), [.equal, .equal, .deletion, .addition, .equal, .equal])
		XCTAssertEqual(edits.flatMap(\.lines), ["a", "b", "c", "X", "d", "e"])
	}

	func testRewritingEveryLineOfALargeFileIsFast() async throws {
		let original = (0..<6_000).map { "old line \($0)" }.joined(separator: "\n") + "\n"
		let replacement = (0..<6_000).map { "new line \($0)" }.joined(separator: "\n") + "\n"
		let start = Date()
		let result = try await ApplyEditsEngine.default.apply(
			request: ApplyEditsRequest(path: "f.txt", mode: .rewrite(newText: replacement, onMissing: .error), verbose: false),
			to: original
		)
		XCTAssertEqual(result.updatedText, replacement)
		XCTAssertLessThan(Date().timeIntervalSince(start), 5.0)
	}

	func testOneLineEditInAVeryLargeFileIsFast() async throws {
		let original = (0..<40_000).map { "line \($0)" }.joined(separator: "\n") + "\n"
		let start = Date()
		let result = try await ApplyEditsEngine.default.apply(
			request: ApplyEditsRequest(
				path: "big.txt",
				mode: .single(search: "line 20000\n", replace: "LINE 20000\n", replaceAll: false),
				verbose: false
			),
			to: original
		)
		XCTAssertTrue(result.updatedText.contains("\nLINE 20000\n"))
		XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
	}
}
