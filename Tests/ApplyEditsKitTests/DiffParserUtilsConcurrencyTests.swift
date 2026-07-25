//
//  DiffParserUtilsConcurrencyTests.swift
//  ApplyEditsKitTests
//
//  Regression tests for the two pieces of shared mutable state in
//  DiffParserUtils that the Swift 6 language-mode migration had to give an
//  explicit ownership story:
//
//   1. `_regexCache` — an `NSCache` kept as-is behind `nonisolated(unsafe)`
//      because NSCache does its own internal locking and its memory-pressure
//      eviction is load-bearing (the cache key embeds a caller-supplied tag,
//      so the key space is unbounded in principle).
//   2. `isDebugEnabled` — a public settable `static var` moved from plain
//      stored storage onto an `Atomic<Bool>`.
//
//  Both tests drive the state from many concurrency domains at once. Without
//  the corresponding fix these paths are data races; the point of the tests
//  is that the observable results stay correct under that concurrency.
//

import XCTest
@testable import ApplyEditsKit

final class DiffParserUtilsConcurrencyTests: XCTestCase {

	// MARK: - _regexCache

	/// Hammers every cached-regex code path from many concurrent child tasks
	/// and asserts each one still returns the value it returns single-threaded.
	///
	/// The workload deliberately mixes cache MISSES (each `tag` interpolates
	/// into a distinct pattern string, so `trimAtSiblingBoundary` compiles and
	/// stores a fresh entry per tag) with cache HITS (the fence helpers use
	/// fixed literal patterns that every task looks up).
	func testConcurrentRegexCacheAccessIsConsistent() async {
		let tags = [
			"description", "search", "content",
			"start_selector", "end_selector",
			"new", "change", "file"
		]

		// Compute the expected answers serially first, on this one thread.
		var expected: [String: String] = [:]
		for tag in tags {
			let text = "payload for \(tag)\n<content>\nsibling body\n"
			expected["trim.\(tag)"] = DiffParserUtils.trimAtSiblingBoundary(text, currentTag: tag)
			expected["post.\(tag)"] = DiffParserUtils.postProcessPayload("===  body \(tag)  ===", forTag: tag)
			expected["extract.\(tag)"] = DiffParserUtils.extractContent(
				from: "<\(tag)>\ninner \(tag)\n</\(tag)>",
				tag: tag,
				flexible: true
			) ?? "<nil>"
		}
		XCTAssertEqual(expected.count, tags.count * 3)

		// Now run the same work from 200 concurrent tasks. Every task races
		// against the others on `_regexCache`.
		let iterations = 200
		let results: [[String: String]] = await withTaskGroup(
			of: [String: String].self
		) { group in
			for i in 0..<iterations {
				let tag = tags[i % tags.count]
				group.addTask {
					let text = "payload for \(tag)\n<content>\nsibling body\n"
					return [
						"trim.\(tag)": DiffParserUtils.trimAtSiblingBoundary(text, currentTag: tag),
						"post.\(tag)": DiffParserUtils.postProcessPayload("===  body \(tag)  ===", forTag: tag),
						"extract.\(tag)": DiffParserUtils.extractContent(
							from: "<\(tag)>\ninner \(tag)\n</\(tag)>",
							tag: tag,
							flexible: true
						) ?? "<nil>"
					]
				}
			}
			var collected: [[String: String]] = []
			for await value in group { collected.append(value) }
			return collected
		}

		XCTAssertEqual(results.count, iterations)
		for observed in results {
			for (key, value) in observed {
				XCTAssertEqual(
					value,
					expected[key],
					"concurrent result for \(key) diverged from the serial result"
				)
			}
		}
	}

	// MARK: - isDebugEnabled

	/// `isDebugEnabled` is public and settable, so a consumer can flip it from
	/// a different concurrency domain while a parse runs. This drives that
	/// exact shape: concurrent writers flipping the flag while concurrent
	/// readers both read it and run a parse that reads it internally.
	///
	/// The assertion is deliberately not "readers saw value X" — `.relaxed`
	/// ordering means a reader may legitimately observe either value. What is
	/// asserted is that every observation is one of the two written values,
	/// that the parse results are unaffected by the flag, and that the flag
	/// round-trips to a definite value once the races are over.
	func testIsDebugEnabledSurvivesConcurrentFlipsAndRestores() async {
		let original = DiffParserUtils.isDebugEnabled
		defer { DiffParserUtils.isDebugEnabled = original }

		let expectedParse = DiffParserUtils.extractContent(
			from: "<description>\nhello\n</description>",
			tag: "description",
			flexible: true
		)

		let observations: [Bool] = await withTaskGroup(of: [Bool].self) { group in
			// Writers: flip the flag from 64 separate tasks.
			for i in 0..<64 {
				group.addTask {
					DiffParserUtils.isDebugEnabled = (i % 2 == 0)
					return []
				}
			}
			// Readers: read the flag and run a parse that reads it internally.
			for _ in 0..<64 {
				group.addTask {
					let seen = DiffParserUtils.isDebugEnabled
					let parsed = DiffParserUtils.extractContent(
						from: "<description>\nhello\n</description>",
						tag: "description",
						flexible: true
					)
					XCTAssertEqual(parsed, expectedParse, "flag flips must not affect parse output")
					return [seen]
				}
			}
			var collected: [Bool] = []
			for await value in group { collected.append(contentsOf: value) }
			return collected
		}

		XCTAssertEqual(observations.count, 64)

		// After the races, the flag still round-trips to a definite value.
		DiffParserUtils.isDebugEnabled = true
		XCTAssertTrue(DiffParserUtils.isDebugEnabled)
		DiffParserUtils.isDebugEnabled = false
		XCTAssertFalse(DiffParserUtils.isDebugEnabled)
	}

	// MARK: - FileChange.dummy

	/// `FileChange.dummy` is a global constant; the migration made it legal by
	/// conforming `FileChange` (and `DiffChunk` / `DiffLine`) to `Sendable`.
	/// Read it from many concurrency domains and confirm every domain sees the
	/// same value, including the same `id` — i.e. it really is one shared
	/// immutable instance and not re-initialized per access.
	func testDummyFileChangeIsReadableFromManyConcurrencyDomains() async {
		let expected = FileChange.dummy

		let observed: [FileChange] = await withTaskGroup(of: FileChange.self) { group in
			for _ in 0..<128 {
				group.addTask { FileChange.dummy }
			}
			var collected: [FileChange] = []
			for await value in group { collected.append(value) }
			return collected
		}

		XCTAssertEqual(observed.count, 128)
		for change in observed {
			XCTAssertEqual(change, expected)
			XCTAssertEqual(change.id, expected.id)
			XCTAssertEqual(change.description, "No change")
			XCTAssertEqual(change.startLine, 0)
			XCTAssertTrue(change.diffChunk.lines.isEmpty)
		}
	}
}
