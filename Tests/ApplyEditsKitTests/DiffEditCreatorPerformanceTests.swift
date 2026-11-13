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

	func testManyScatteredChangesBeyondTheEditDistanceCapStillDiffPrecisely() {
		let old = (0..<4_000).map { "line \($0)" }
		var new = old
		for index in stride(from: 0, to: new.count, by: 3) {
			new[index] = "changed \(index)"
		}
		let start = Date()
		let edits = DiffEditCreator.myersDiff(oldLines: old, newLines: new)
		XCTAssertLessThan(Date().timeIntervalSince(start), 5.0)
		XCTAssertEqual(edits.filter { $0.type == .deletion }.count, 1_334)
		XCTAssertEqual(edits.filter { $0.type == .addition }.count, 1_334)
		XCTAssertEqual(edits.filter { $0.type != .addition }.flatMap(\.lines), old)
		XCTAssertEqual(edits.filter { $0.type != .deletion }.flatMap(\.lines), new)
	}

	func testReplaceAllTouchingAThirdOfALargeFileReportsOnlyTheChangedLines() async throws {
		let original = (0..<4_000).map { $0 % 3 == 0 ? "call old(\($0))" : "keep \($0)" }.joined(separator: "\n") + "\n"
		let result = try await ApplyEditsEngine.default.apply(
			request: ApplyEditsRequest(path: "f.txt", mode: .single(search: "old(", replace: "new(", replaceAll: true), verbose: false),
			to: original
		)
		XCTAssertEqual(result.stats?.linesChanged, 1_334)
	}

	func testEditScriptsReconstructBothSidesForRandomInputs() {
		var state: UInt64 = 0x9E37_79B9_7F4A_7C15
		func next(_ bound: Int) -> Int {
			state = state &* 6364136223846793005 &+ 1442695040888963407
			return Int((state >> 33) % UInt64(bound))
		}
		func check(_ old: [String], _ new: [String]) {
			let edits = DiffEditCreator.myersDiff(oldLines: old, newLines: new)
			XCTAssertEqual(edits.filter { $0.type != .addition }.flatMap(\.lines), old)
			XCTAssertEqual(edits.filter { $0.type != .deletion }.flatMap(\.lines), new)
		}
		for _ in 0..<500 {
			let old = (0..<next(12)).map { _ in String(next(4)) }
			let new = (0..<next(12)).map { _ in String(next(4)) }
			check(old, new)
		}
		for alphabet in [50, 3_000, 20_000] {
			let old = (0..<6_000).map { _ in "w\(next(alphabet))" }
			var new = old
			for _ in 0..<3_000 {
				switch next(3) {
				case 0: new[next(new.count)] = "x\(next(alphabet))"
				case 1: new.insert("y\(next(alphabet))", at: next(new.count))
				default: if new.count > 1 { new.remove(at: next(new.count)) }
				}
			}
			check(old, new)
		}
	}
}
