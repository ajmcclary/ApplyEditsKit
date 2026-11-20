import XCTest
@testable import ApplyEditsKit

/// `DiffApplicator.revert` must be the exact inverse of `DiffApplicator.apply`:
/// for a chunk that fits `original` at `start`,
/// `revert(apply(original, chunk), chunk) == original`.
///
/// Every expectation here is computed from the ORIGINAL and MODIFIED text
/// (by splicing the chunk's old/new segments into the original), never by
/// replaying the implementation's own cursor logic. RepoPrompt's Undo button
/// reaches `revert` through `ChangeApplier.revert` → `ChangeManager.revertChange`
/// and saves the result to disk, so a wrong revert is silent data corruption.
final class DiffApplicatorRevertTests: XCTestCase {

	// MARK: - Concrete cases

	func testRevertingAMiddleDeletionRestoresTheDeletedLine() throws {
		let original = ["A", "B", "C"]
		let chunk = makeChunk([" A", "-B", " C"], start: 0)
		try assertRoundTrip(original: original, chunk: chunk, start: 0, expectedApplied: ["A", "C"])
	}

	func testRevertingAContextFreeDeletionRestoresTheDeletedLine() throws {
		try assertRoundTrip(original: ["A", "B", "C"], chunk: makeChunk(["-B"], start: 1), start: 1, expectedApplied: ["A", "C"])
	}

	func testRevertingAnInsertionAtFileStartRemovesIt() throws {
		try assertRoundTrip(original: ["A", "B"], chunk: makeChunk(["+X", " A"], start: 0), start: 0, expectedApplied: ["X", "A", "B"])
	}

	func testRevertingAnInsertionAtFileEndRemovesIt() throws {
		try assertRoundTrip(original: ["A", "B"], chunk: makeChunk([" B", "+X"], start: 1), start: 1, expectedApplied: ["A", "B", "X"])
		try assertRoundTrip(original: ["A", "B"], chunk: makeChunk(["+X"], start: 2), start: 2, expectedApplied: ["A", "B", "X"])
	}

	func testRevertingAReplacementOfTheLastLineRestoresIt() throws {
		try assertRoundTrip(original: ["A", "B", "C"], chunk: makeChunk([" B", "-C", "+D"], start: 1), start: 1, expectedApplied: ["A", "B", "D"])
	}

	func testRevertingAReplacementOfTheFirstLineRestoresIt() throws {
		try assertRoundTrip(original: ["A", "B", "C"], chunk: makeChunk(["-A", "+Z", " B"], start: 0), start: 0, expectedApplied: ["Z", "B", "C"])
	}

	func testRevertingAMultiLineReplacementRestoresTheOriginalBlock() throws {
		let original = ["A", "B", "C", "D"]
		let chunk = makeChunk([" A", "-B", "-C", "+X", "+Y", "+Z", " D"], start: 0)
		try assertRoundTrip(original: original, chunk: chunk, start: 0, expectedApplied: ["A", "X", "Y", "Z", "D"])
	}

	func testRevertingAWholeFileDeletionRestoresEveryLine() throws {
		let original = ["A", "B", "C"]
		let chunk = makeChunk(["-A", "-B", "-C"], start: 0)
		try assertRoundTrip(original: original, chunk: chunk, start: 0, expectedApplied: [])
	}

	func testRevertingTheCreationOfAFileLeavesItEmpty() throws {
		try assertRoundTrip(original: [], chunk: makeChunk(["+A", "+B"], start: 0), start: 0, expectedApplied: ["A", "B"])
	}

	func testRevertThrowsWhenTheChunkAdditionsAreNotInTheContent() {
		// `apply` refuses a chunk that runs past the end; `revert` must too,
		// rather than silently producing a partially reverted file.
		let chunk = makeChunk([" A", "+X", "+Y"], start: 0)
		XCTAssertThrowsError(try DiffApplicator.revert(chunk, from: ["A", "X"], startingAt: 0))
		XCTAssertThrowsError(try DiffApplicator.revert(chunk, from: ["A"], startingAt: 3))
	}

	// MARK: - Property: revert(apply(x)) == x

	/// Arbitrary chunks that fit the original: a random window, then a random
	/// interleaving of context / removal / addition lines over it.
	func testRevertInvertsApplyForSeededRandomChunks() throws {
		var rng = SplitMix64(seed: 0xD1FF_A991_1CA7_0001)
		for iteration in 0..<3_000 {
			let original = randomLines(&rng, count: Int.random(in: 0...10, using: &rng))
			let start = Int.random(in: 0...original.count, using: &rng)
			let (chunk, end) = randomChunk(fitting: original, at: start, &rng)
			let expectedApplied = Array(original[..<start]) + newSegment(of: chunk) + Array(original[end...])
			try assertRoundTrip(original: original, chunk: chunk, start: start, expectedApplied: expectedApplied,
								message: "iteration \(iteration): original=\(original) chunk=\(chunk.lines.map(\.rawContent)) start=\(start)")
		}
	}

	/// Real hunks from `UnifiedDiffGenerator.diffChunks` (1-based start lines),
	/// each applied and reverted on its own — the shape of the original repro.
	/// Hunks whose old side does not match the original at their start line
	/// are skipped: some generated hunks drop context lines or carry a wrong
	/// start after a context split (a separate `UnifiedDiffGenerator.hunks`
	/// defect), so they are not a valid round-trip input for any applicator.
	func testRevertInvertsApplyForGeneratedHunks() throws {
		var rng = SplitMix64(seed: 0xD1FF_A991_1CA7_0002)
		var usableHunks = 0
		for iteration in 0..<600 {
			let (original, modified) = randomEditPair(&rng)
			let context = Int.random(in: 0...3, using: &rng)
			for chunk in UnifiedDiffGenerator.diffChunks(oldLines: original, newLines: modified, context: context) {
				let start = chunk.startLine - 1
				let end = start + oldSegment(of: chunk).count
				guard start >= 0, end <= original.count, Array(original[start..<end]) == oldSegment(of: chunk) else { continue }
				usableHunks += 1
				let expectedApplied = Array(original[..<start]) + newSegment(of: chunk) + Array(original[end...])
				try assertRoundTrip(original: original, chunk: chunk, start: start, expectedApplied: expectedApplied,
									message: "iteration \(iteration): original=\(original) modified=\(modified)")
			}
		}
		XCTAssertGreaterThan(usableHunks, 400, "generator produced too few usable hunks to be meaningful")
	}

	// MARK: - ChangeManager.revertChange (the Undo path)

	func testChangeManagerUndoOfADeletionRestoresTheFile() {
		let change = FileChange(startLine: 0, description: "delete B", diffChunk: makeChunk([" A", "-B", " C"], start: 0))
		let manager = ChangeManager(fileContent: ["A", "B", "C"], changes: [change], lineEnding: "\n", fileAction: .modify, hadTrailingNewline: true)
		XCTAssertNil(manager.applyChange(change).error)
		XCTAssertEqual(manager.getUpdatedContent(), "A\nC\n")
		let reverted = manager.revertChange(change)
		XCTAssertNil(reverted.error)
		XCTAssertEqual(reverted.updatedContent, ["A", "B", "C"])
		XCTAssertEqual(reverted.appliedChangeIds, [])
		XCTAssertEqual(manager.getUpdatedContent(), "A\nB\nC\n")
	}

	func testChangeManagerUndoOfAWholeFileDeletionRestoresTheFile() {
		let change = FileChange(startLine: 0, description: "delete all", diffChunk: makeChunk(["-A", "-B"], start: 0))
		let manager = ChangeManager(fileContent: ["A", "B"], changes: [change], lineEnding: "\n", fileAction: .modify)
		XCTAssertNil(manager.applyChange(change).error)
		XCTAssertEqual(manager.currentContentLines(), [])
		XCTAssertNil(manager.revertChange(change).error)
		XCTAssertEqual(manager.currentContentLines(), ["A", "B"])
	}

	/// Several disjoint chunks over one file. Apply all of them (ascending, as
	/// "accept all" does), then undo them one at a time in a seeded random
	/// order. After each undo the file must equal the original with exactly
	/// the still-applied chunks spliced in.
	func testChangeManagerUndoInAnyOrderRestoresTheExpectedContent() {
		var rng = SplitMix64(seed: 0xD1FF_A991_1CA7_0003)
		var multiChangeCases = 0
		for iteration in 0..<1_000 {
			let original = randomLines(&rng, count: Int.random(in: 0...20, using: &rng))
			var changes: [FileChange] = []
			var cursor = Int.random(in: 0...min(2, original.count), using: &rng)
			while cursor <= original.count && changes.count < 4 {
				let (chunk, end) = randomChunk(fitting: original, at: cursor, &rng)
				changes.append(FileChange(startLine: cursor, description: "", diffChunk: chunk))
				cursor = end + Int.random(in: 1...3, using: &rng)
			}
			if changes.count > 1 { multiChangeCases += 1 }
			let context = "iteration \(iteration): original=\(original) changes=\(changes.map { ($0.startLine, $0.diffChunk.lines.map(\.rawContent)) })"

			let manager = ChangeManager(fileContent: original, changes: changes, lineEnding: "\n", fileAction: .modify)
			for change in changes {
				XCTAssertNil(manager.applyChange(change).error, context)
			}
			let allIDs = Set(changes.map(\.id))
			XCTAssertEqual(manager.currentContentLines(), splice(original: original, changes: changes, applied: allIDs),
						   "accept-all precondition. \(context)")

			var applied = allIDs
			let order = changes.shuffled(using: &rng)
			for change in order {
				let result = manager.revertChange(change)
				XCTAssertNil(result.error, "undo order \(order.map(\.startLine)). \(context)")
				applied.remove(change.id)
				XCTAssertEqual(result.appliedChangeIds, applied, context)
				let expected = splice(original: original, changes: changes, applied: applied)
				guard manager.currentContentLines() == expected else {
					XCTFail("undo order \(order.map(\.startLine)): got \(manager.currentContentLines()), expected \(expected). \(context)")
					return
				}
			}
		}
		XCTAssertGreaterThan(multiChangeCases, 300, "too few multi-change cases to exercise ordering")
	}

	// MARK: - Helpers

	private func assertRoundTrip(original: [String], chunk: DiffChunk, start: Int, expectedApplied: [String],
								 message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
		let applied = try DiffApplicator.apply(chunk, to: original, startingAt: start)
		XCTAssertEqual(applied, expectedApplied, "apply precondition. \(message)", file: file, line: line)
		let reverted = try DiffApplicator.revert(chunk, from: applied, startingAt: start)
		XCTAssertEqual(reverted, original, "revert did not restore the original. \(message)", file: file, line: line)
	}

	private func makeChunk(_ rawLines: [String], start: Int) -> DiffChunk {
		DiffChunk(lines: rawLines.map { DiffLine(content: $0) }, startLine: start)
	}

	private func oldSegment(of chunk: DiffChunk) -> [String] {
		chunk.lines.filter { $0.type != .addition }.map(\.content)
	}

	private func newSegment(of chunk: DiffChunk) -> [String] {
		chunk.lines.filter { $0.type != .removal }.map(\.content)
	}

	/// The original text with each applied change's old segment replaced by its
	/// new segment. Changes carry original (pre-application) 0-based positions
	/// and do not overlap.
	private func splice(original: [String], changes: [FileChange], applied: Set<UUID>) -> [String] {
		var result: [String] = []
		var cursor = 0
		for change in changes.sorted(by: { $0.startLine < $1.startLine }) where applied.contains(change.id) {
			result += original[cursor..<change.startLine]
			result += newSegment(of: change.diffChunk)
			cursor = change.startLine + oldSegment(of: change.diffChunk).count
		}
		result += original[cursor...]
		return result
	}

	/// A random chunk over `original` starting at `start`: an interleaving of
	/// context / removal / addition lines with at least one change. Returns
	/// the chunk and the (exclusive) end of the original region it covers.
	private func randomChunk(fitting original: [String], at start: Int, _ rng: inout SplitMix64) -> (DiffChunk, end: Int) {
		var cursor = start
		var rawLines: [String] = []
		for _ in 0..<Int.random(in: 1...6, using: &rng) {
			let canConsume = cursor < original.count
			switch Int.random(in: 0..<3, using: &rng) {
			case 0 where canConsume:
				rawLines.append(" " + original[cursor]); cursor += 1
			case 1 where canConsume:
				rawLines.append("-" + original[cursor]); cursor += 1
			default:
				rawLines.append("+" + randomLine(&rng))
			}
		}
		if !rawLines.contains(where: { !$0.hasPrefix(" ") }) {
			rawLines.append("+" + randomLine(&rng))
		}
		return (makeChunk(rawLines, start: start), cursor)
	}

	/// A small alphabet so duplicate lines (the case a cursor bug confuses) are common.
	private func randomLine(_ rng: inout SplitMix64) -> String {
		["a", "b", "c", "d", "e", "}", ""].randomElement(using: &rng)!
	}

	private func randomLines(_ rng: inout SplitMix64, count: Int) -> [String] {
		(0..<count).map { _ in randomLine(&rng) }
	}

	private func randomEditPair(_ rng: inout SplitMix64) -> (original: [String], modified: [String]) {
		let original = (0..<Int.random(in: 0...24, using: &rng)).map { "L\($0)-\(randomLine(&rng))" }
		var modified = original
		for _ in 0..<Int.random(in: 1...4, using: &rng) {
			let at = Int.random(in: 0...modified.count, using: &rng)
			switch Int.random(in: 0..<3, using: &rng) {
			case 0:
				modified.insert(contentsOf: randomLines(&rng, count: Int.random(in: 1...3, using: &rng)).map { "new-\($0)" }, at: at)
			case 1 where at < modified.count:
				modified.removeSubrange(at..<min(modified.count, at + Int.random(in: 1...3, using: &rng)))
			default:
				if at < modified.count { modified[at] = "changed-\(randomLine(&rng))" } else { modified.append("tail") }
			}
		}
		return (original, modified)
	}
}

/// Deterministic generator so every failure reproduces exactly.
private struct SplitMix64: RandomNumberGenerator {
	private var state: UInt64
	init(seed: UInt64) { state = seed }
	mutating func next() -> UInt64 {
		state &+= 0x9E37_79B9_7F4A_7C15
		var z = state
		z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
		z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
		return z ^ (z >> 31)
	}
}
