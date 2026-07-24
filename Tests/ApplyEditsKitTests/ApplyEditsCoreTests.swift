//
//  ApplyEditsCoreTests.swift
//  RepoPromptTests
//

import XCTest
@testable import ApplyEditsKit

final class ApplyEditsCoreTests: XCTestCase {
	private let engine = ApplyEditsEngine.default

	private func makeRequest(
		path: String = "file.swift",
		mode: ApplyEditsMode,
		verbose: Bool = false
	) -> ApplyEditsRequest {
		ApplyEditsRequest(path: path, mode: mode, verbose: verbose)
	}

	func testRewriteUpdatesTextAndDiffWhenVerbose() async throws {
		let original = "old\n"
		let request = makeRequest(
			mode: .rewrite(newText: "new\n", onMissing: .error),
			verbose: true
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .success)
		XCTAssertEqual(result.updatedText, "new\n")
		XCTAssertNotNil(result.unifiedDiff)
		XCTAssertNotNil(result.stats)
	}

	func testUnifiedDiffForToolCardFallsBackWhenVerboseFalse() async throws {
		let original = "one\ntwo\nthree\n"
		let request = makeRequest(
			path: "sample.swift",
			mode: .single(search: "two", replace: "2", replaceAll: false),
			verbose: false
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertNil(result.unifiedDiff)
		let displayDiff = result.unifiedDiffForToolCard(filePath: request.path)
		XCTAssertNotNil(displayDiff)
		XCTAssertTrue(displayDiff?.contains("@@") == true)
		XCTAssertTrue(displayDiff?.contains("sample.swift") == true)
		XCTAssertTrue(displayDiff?.contains(" one") == true)
		XCTAssertTrue(displayDiff?.contains(" three") == true)
	}

	func testUnifiedDiffForToolCardPrefersVerboseDiff() async throws {
		let original = "old\n"
		let request = makeRequest(
			path: "sample.swift",
			mode: .rewrite(newText: "new\n", onMissing: .error),
			verbose: true
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertNotNil(result.unifiedDiff)
		let displayDiff = result.unifiedDiffForToolCard(filePath: request.path)
		XCTAssertEqual(displayDiff, result.unifiedDiff)
	}

	func testDefaultExecutionOptionsBuildToolCardDiff() async throws {
		XCTAssertTrue(ApplyEditsExecutionOptions.default.includeToolCardUnifiedDiff)

		let request = makeRequest(
			path: "sample.swift",
			mode: .single(search: "two", replace: "2", replaceAll: false),
			verbose: false
		)

		let result = try await engine.apply(request: request, to: "one\ntwo\nthree\n")
		XCTAssertNil(result.unifiedDiff)
		XCTAssertNotNil(result.toolCardUnifiedDiff)
		XCTAssertEqual(result.unifiedDiffForToolCard(filePath: request.path), result.toolCardUnifiedDiff)
	}

	func testDelegateSandboxExecutionOptionsSkipEagerToolCardDiffButFallbackWorks() async throws {
		XCTAssertFalse(ApplyEditsExecutionOptions.delegateSandbox.includeToolCardUnifiedDiff)

		let request = makeRequest(
			path: "sample.swift",
			mode: .single(search: "two", replace: "2", replaceAll: false),
			verbose: false
		)

		let result = try await engine.apply(
			request: request,
			to: "one\ntwo\nthree\n",
			options: .delegateSandbox
		)
		XCTAssertNil(result.unifiedDiff)
		XCTAssertNil(result.toolCardUnifiedDiff)
		let displayDiff = result.unifiedDiffForToolCard(filePath: request.path)
		XCTAssertNotNil(displayDiff)
		XCTAssertTrue(displayDiff?.contains("@@") == true)
		XCTAssertTrue(displayDiff?.contains("+2") == true)
	}

	func testDelegateSandboxExecutionOptionsKeepVerboseDiffWithoutToolCardDiff() async throws {
		let request = makeRequest(
			path: "sample.swift",
			mode: .rewrite(newText: "new\n", onMissing: .error),
			verbose: true
		)

		let result = try await engine.apply(
			request: request,
			to: "old\n",
			options: .delegateSandbox
		)
		XCTAssertNotNil(result.unifiedDiff)
		XCTAssertNil(result.toolCardUnifiedDiff)
		XCTAssertEqual(result.unifiedDiffForToolCard(filePath: request.path), result.unifiedDiff)
	}

	func testUnifiedDiffForToolCardFallbackDecodesEncodedIndentation() {
		let chunk = DiffChunk(
			lines: [
				DiffLine(content: "-<t1>old"),
				DiffLine(content: "+<t2>new")
			],
			startLine: 1
		)
		let result = ApplyEditsResult(
			updatedText: "\t\tnew\n",
			diffChunks: [chunk],
			unifiedDiff: nil,
			toolCardUnifiedDiff: nil,
			stats: ApplyEditsStats(linesChanged: 1, chunks: 1),
			note: nil,
			fileCreated: false,
			fileOverwritten: false,
			editsRequested: 1,
			editsApplied: 1,
			status: .success,
			outcomes: nil
		)

		let displayDiff = result.unifiedDiffForToolCard(filePath: "sample.swift")
		XCTAssertNotNil(displayDiff)
		XCTAssertFalse(displayDiff?.contains("<t1>") == true)
		XCTAssertFalse(displayDiff?.contains("<t2>") == true)
		XCTAssertTrue(displayDiff?.contains("-\told") == true)
		XCTAssertTrue(displayDiff?.contains("+\t\tnew") == true)
	}

	func testToolCardDiffFallbackPathDecodesEncodedIndentation() async throws {
		struct StubDiffGenerator: DiffChunkGenerator {
			let chunk: DiffChunk

			func makeDiffChunks(
				filePath: String,
				originalText: String,
				search: String?,
				replace: String,
				replaceAll: Bool,
				treatAsRewrite: Bool
			) async throws -> (chunks: [DiffChunk], fileAction: FileAction) {
				([chunk], .modify)
			}
		}

		struct NoopDiffApplier: DiffChunkApplier {
			func apply(chunks: [DiffChunk], to originalText: String, fileAction: FileAction) throws -> String {
				// Force buildToolCardUnifiedDiff to use its fallback path.
				originalText
			}
		}

		struct StubUnifiedDiffRenderer: UnifiedDiffRendering {
			func render(filePath: String, chunks: [DiffChunk]) -> String {
				""
			}
		}

		let chunk = DiffChunk(
			lines: [
				DiffLine(content: "-<t1>old"),
				DiffLine(content: "+<t2>new")
			],
			startLine: 1
		)
		let customEngine = ApplyEditsEngine(
			diffEngine: StubDiffGenerator(chunk: chunk),
			patchApplier: NoopDiffApplier(),
			unifiedDiffRenderer: StubUnifiedDiffRenderer()
		)
		let request = makeRequest(
			path: "sample.swift",
			mode: .single(search: "old", replace: "new", replaceAll: false),
			verbose: false
		)

		let result = try await customEngine.apply(request: request, to: "old\n")
		let displayDiff = result.unifiedDiffForToolCard(filePath: request.path)
		XCTAssertNotNil(displayDiff)
		XCTAssertFalse(displayDiff?.contains("<t1>") == true)
		XCTAssertFalse(displayDiff?.contains("<t2>") == true)
		XCTAssertTrue(displayDiff?.contains("-\told") == true)
		XCTAssertTrue(displayDiff?.contains("+\t\tnew") == true)
	}

	func testSingleReplaceSuccess() async throws {
		let original = "one\ntwo\nthree\n"
		let request = makeRequest(
			mode: .single(search: "two", replace: "2", replaceAll: false)
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .success)
		XCTAssertTrue(result.updatedText.contains("2"))
		XCTAssertFalse(result.updatedText.contains("two"))
	}

	func testSingleReplaceAllResolvesMultipleMatches() async throws {
		let original = "dup\ndup\n"
		let request = makeRequest(
			mode: .single(search: "dup", replace: "ok", replaceAll: true)
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .success)
		XCTAssertEqual(result.updatedText, "ok\nok\n")
	}

	func testSingleReplaceAmbiguousThrows() async {
		let original = "dup\ndup\n"
		let request = makeRequest(
			mode: .single(search: "dup", replace: "ok", replaceAll: false)
		)

		await XCTAssertThrowsErrorAsync(try await engine.apply(request: request, to: original)) { error in
			guard case ApplyEditsError.invalidParams(let message) = error else {
				return XCTFail("Expected invalidParams error")
			}
			XCTAssertTrue(message.contains("multiple locations"))
		}
	}

	func testSingleFallbackDecodesEscapedNewlinesWhenRawSearchMissing() async throws {
		let original = "alpha\nbeta\n"
		let request = makeRequest(
			mode: .single(search: "alpha\\nbeta", replace: "one\\ntwo", replaceAll: false)
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .success)
		XCTAssertEqual(result.updatedText, "one\ntwo\n")
	}

	func testSingleFallbackDoesNotDecodeWhenLiteralMatchExists() async throws {
		let original = "alpha\\nbeta\n"
		let request = makeRequest(
			mode: .single(search: "alpha\\nbeta", replace: "one\\ntwo", replaceAll: false)
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .success)
		XCTAssertEqual(result.updatedText, "one\\ntwo\n")
	}

	func testSingleReplaceAllNoMatchReturnsReplaceAllSpecificMessage() async {
		let original = "one\ntwo\n"
		let request = makeRequest(
			mode: .single(search: "missing", replace: "ok", replaceAll: true)
		)

		await XCTAssertThrowsErrorAsync(try await engine.apply(request: request, to: original)) { error in
			guard case ApplyEditsError.invalidParams(let message) = error else {
				return XCTFail("Expected invalidParams error")
			}
			XCTAssertTrue(message.contains("no literal matches for replace_all"))
		}
	}

	func testBatchLiteralFastPathIncludesNoteAndOutcomes() async throws {
		let original = "Hello\nGoodbye\n"
		let request = makeRequest(
			mode: .batch([
				ApplyEditsOperation(search: "Hello", replace: "Hi", replaceAll: false),
				ApplyEditsOperation(search: "Goodbye", replace: "Bye", replaceAll: false)
			]),
			verbose: true
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .success)
		XCTAssertEqual(result.note, "Applied via exact literal replacement")
		XCTAssertEqual(result.outcomes?.count, 2)
		XCTAssertTrue(result.updatedText.contains("Hi"))
		XCTAssertTrue(result.updatedText.contains("Bye"))
	}

	func testBatchLiteralDoesNotEmitNoiseForMixedLineEndings() async throws {
		let original = "import SwiftUI\r\n\r\n\tstruct Foo {\n\t\tlet value = 1\r\n\t}\n\tstruct Bar {\r\n\t\tlet value = 2\n\t}\r\n"
		let generator = DefaultDiffChunkGenerator()

		let (chunks, _) = try await generator.makeDiffChunks(
			filePath: "file.swift",
			originalText: original,
			search: "\tstruct Bar {",
			replace: "\tstruct Baz {",
			replaceAll: false,
			treatAsRewrite: false
		)

		let decodedLines = chunks.flatMap { $0.getChunkWithDecodedIndentation().lines }
		for idx in 0..<(decodedLines.count - 1) {
			let current = decodedLines[idx]
			let next = decodedLines[idx + 1]
			if current.type == .removal, next.type == .addition, current.content == next.content {
				XCTFail("Found identical remove/add pair at index \(idx): \(current.content)")
			}
		}
		XCTAssertFalse(decodedLines.contains { $0.type == .removal && $0.content == "import SwiftUI" })
		XCTAssertFalse(decodedLines.contains { $0.type == .addition && $0.content == "import SwiftUI" })
		XCTAssertTrue(decodedLines.contains { $0.type == .removal && $0.content == "\tstruct Bar {" })
		XCTAssertTrue(decodedLines.contains { $0.type == .addition && $0.content == "\tstruct Baz {" })
	}

	func testBatchFallbackDecodesEscapedNewlinesWhenRawSearchMissing() async throws {
		let original = "one\ntwo\n"
		let request = makeRequest(
			mode: .batch([
				ApplyEditsOperation(search: "one\\ntwo", replace: "1\\n2", replaceAll: false)
			])
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .success)
		XCTAssertEqual(result.updatedText, "1\n2\n")
	}

	func testBatchReturnsOutcomesEvenWhenVerboseFalse() async throws {
		let original = "    foo\n    bar\n"
		let request = makeRequest(
			mode: .batch([
				ApplyEditsOperation(search: "\tfoo", replace: "\tbaz", replaceAll: false)
			]),
			verbose: false
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .success)
		XCTAssertNotNil(result.outcomes)
		XCTAssertTrue(result.updatedText.contains("baz"))
	}

	func testBatchPartialSuccess() async throws {
		let original = "One\nTwo\n"
		let request = makeRequest(
			mode: .batch([
				ApplyEditsOperation(search: "One", replace: "1", replaceAll: false),
				ApplyEditsOperation(search: "Missing", replace: "X", replaceAll: false)
			])
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .partial)
		XCTAssertEqual(result.editsApplied, 1)
		XCTAssertTrue(result.updatedText.contains("1"))
		XCTAssertNotNil(result.outcomes)
	}

	func testBatchAllFailReturnsFailed() async throws {
		let original = "One\nTwo\n"
		let request = makeRequest(
			mode: .batch([
				ApplyEditsOperation(search: "Missing", replace: "X", replaceAll: false)
			])
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .failed)
		XCTAssertEqual(result.editsApplied, 0)
		XCTAssertEqual(result.updatedText, original)
		XCTAssertTrue(result.diffChunks.isEmpty)
		XCTAssertNil(result.unifiedDiff)
		XCTAssertNil(result.stats)
	}

	func testBatchPreservesTabIndentation() async throws {
		let original = "\tfoo\n\tbar\n"
		let request = makeRequest(
			mode: .batch([
				ApplyEditsOperation(search: "\tfoo", replace: "\tBAZ", replaceAll: false)
			])
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .success)
		XCTAssertTrue(result.updatedText.contains("\tBAZ"))
	}

	func testBatchPreservesSpaceIndentation() async throws {
		let original = "    foo\n    bar\n"
		let request = makeRequest(
			mode: .batch([
				ApplyEditsOperation(search: "    foo", replace: "    BAZ", replaceAll: false)
			])
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .success)
		XCTAssertTrue(result.updatedText.contains("    BAZ"))
		XCTAssertFalse(result.updatedText.contains("\t"))
	}

	func testBatchEscapedLeadingTabWithoutEscapeDecodingIsPromoted() async throws {
		let original = "    foo\n    bar\n"
		let request = makeRequest(
			mode: .batch([
				ApplyEditsOperation(search: "\\tfoo", replace: "\\tBAZ", replaceAll: false)
			])
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .success)
		XCTAssertTrue(result.updatedText.contains("    BAZ"))
	}

	func testBatchEscapedLeadingTabWithEscapeDecodingMatchesSpaceIndentedFile() async throws {
		let original = "    foo\n    bar\n"
		let request = makeRequest(
			mode: .batch([
				ApplyEditsOperation(search: "\tfoo", replace: "\tBAZ", replaceAll: false)
			])
		)

		let result = try await engine.apply(request: request, to: original)
		XCTAssertEqual(result.status, .success)
		XCTAssertTrue(result.updatedText.contains("    BAZ"))
	}
}




// MARK: - Merged from ApplyEditsServiceTests.swift


extension ApplyEditsCoreTests {
	func testMissingFileRewriteCreateWritesFile() async throws {
		let host = InMemoryFileEditHost()
		let service = ApplyEditsService(engine: .default, host: host)
		let request = makeRequest(
			path: "new.swift",
			mode: .rewrite(newText: "content\n", onMissing: .create),
			verbose: true
		)

		let result = try await service.run(request)
		XCTAssertEqual(result.fileCreated, true)
		XCTAssertNotNil(result.unifiedDiff)
		XCTAssertTrue(result.unifiedDiff?.contains("@@ -1,0 +1,1 @@") == true)

		let stored = await host.currentText(path: "new.swift")
		XCTAssertEqual(stored, "content\n")
		let writes = await host.writes
		XCTAssertEqual(writes.count, 1)
		XCTAssertEqual(writes.first?.overwrite, false)
	}

	func testMissingFileRewriteCreateWithDelegateSandboxOptionsSkipsToolCardDiff() async throws {
		let host = InMemoryFileEditHost()
		let service = ApplyEditsService(engine: .default, host: host)
		let request = makeRequest(
			path: "new.swift",
			mode: .rewrite(newText: "content\n", onMissing: .create),
			verbose: true
		)

		let result = try await service.run(request, options: .delegateSandbox)
		XCTAssertEqual(result.fileCreated, true)
		XCTAssertNotNil(result.unifiedDiff)
		XCTAssertNil(result.toolCardUnifiedDiff)
		XCTAssertEqual(result.unifiedDiffForToolCard(filePath: request.path), result.unifiedDiff)

		let stored = await host.currentText(path: "new.swift")
		XCTAssertEqual(stored, "content\n")
	}

	func testPartialSuccessWritesUpdatedContent() async throws {
		let host = InMemoryFileEditHost(files: ["file.swift": "One\nTwo\n"])
		let service = ApplyEditsService(engine: .default, host: host)
		let request = makeRequest(
			path: "file.swift",
			mode: .batch([
				ApplyEditsOperation(search: "One", replace: "1", replaceAll: false),
				ApplyEditsOperation(search: "Missing", replace: "X", replaceAll: false)
			])
		)

		let result = try await service.run(request)
		XCTAssertEqual(result.status, .partial)
		let writes = await host.writes
		XCTAssertEqual(writes.count, 1)
		XCTAssertEqual(writes.first?.overwrite, true)
		let stored = await host.currentText(path: "file.swift")
		XCTAssertEqual(stored, result.updatedText)
	}

	func testWriteFailurePropagatesError() async {
		struct WriteFailure: Error {}

		actor FailingWriteHost: FileEditHost {
			func fileExists(path: String) async -> Bool { true }
			func readText(path: String) async throws -> String { "Hello\n" }
			func writeText(path: String, content: String, overwrite: Bool) async throws {
				throw WriteFailure()
			}
		}

		let host = FailingWriteHost()
		let service = ApplyEditsService(engine: .default, host: host)
		let request = makeRequest(
			path: "file.swift",
			mode: .single(search: "Hello", replace: "Hi", replaceAll: false)
		)

		await XCTAssertThrowsErrorAsync(try await service.run(request)) { error in
			XCTAssertTrue(error is WriteFailure)
		}
	}

	func testMissingFileRewriteErrorThrows() async {
		let host = InMemoryFileEditHost()
		let service = ApplyEditsService(engine: .default, host: host)
		let request = makeRequest(
			path: "missing.swift",
			mode: .rewrite(newText: "content", onMissing: .error)
		)

		await XCTAssertThrowsErrorAsync(try await service.run(request)) { error in
			guard case ApplyEditsError.invalidParams(let message) = error else {
				return XCTFail("Expected invalidParams error")
			}
			XCTAssertTrue(message.contains("on_missing=\"create\""))
		}
	}

	func testExistingFileAllFailDoesNotWrite() async throws {
		let host = InMemoryFileEditHost(files: ["file.swift": "One\n"])
		let service = ApplyEditsService(engine: .default, host: host)
		let request = makeRequest(
			path: "file.swift",
			mode: .batch([
				ApplyEditsOperation(search: "Missing", replace: "X", replaceAll: false)
			])
		)

		let result = try await service.run(request)
		XCTAssertEqual(result.status, .failed)
		let writes = await host.writes
		XCTAssertEqual(writes.count, 0)
		let stored = await host.currentText(path: "file.swift")
		XCTAssertEqual(stored, "One\n")
	}

	func testExistingFileSingleSuccessWrites() async throws {
		let host = InMemoryFileEditHost(files: ["file.swift": "Hello\n"])
		let service = ApplyEditsService(engine: .default, host: host)
		let request = makeRequest(
			path: "file.swift",
			mode: .single(search: "Hello", replace: "Hi", replaceAll: false)
		)

		let result = try await service.run(request)
		XCTAssertEqual(result.status, .success)
		let writes = await host.writes
		XCTAssertEqual(writes.count, 1)
		XCTAssertEqual(writes.first?.overwrite, true)
		let stored = await host.currentText(path: "file.swift")
		XCTAssertEqual(stored, "Hi\n")
	}
}



// MARK: - Merged from ApplyEditsUnifiedDiffGoldenTests.swift


extension ApplyEditsCoreTests {
	func testUnifiedDiffSingleLineReplaceGolden() async throws {
		let original = "alpha\nbravo\ncharlie\n"
		let request = makeRequest(mode: .single(search: "bravo", replace: "beta", replaceAll: false), verbose: true)

		let result = try await engine.apply(request: request, to: original)
		let expected = "--- a/file.swift\n+++ b/file.swift\n@@ -1,2 +1,2 @@\n alpha\n-bravo\n+beta\n"
		XCTAssertEqual(result.unifiedDiff, expected)
	}

	func testUnifiedDiffMultipleHunksGolden() async throws {
		let original = [
			"line1",
			"line2",
			"line3",
			"line4",
			"line5",
			"line6",
			"line7",
			"line8",
			"line9",
			"line10",
			"line11",
			"line12",
			"line13",
			"line14",
			"line15"
		].joined(separator: "\n") + "\n"

		let request = makeRequest(mode: .batch([
			ApplyEditsOperation(search: "line2", replace: "LINE2", replaceAll: false),
			ApplyEditsOperation(search: "line14", replace: "LINE14", replaceAll: false)
		]), verbose: true)

		let result = try await engine.apply(request: request, to: original)
		let expected = "--- a/file.swift\n+++ b/file.swift\n@@ -1,2 +1,2 @@\n line1\n-line2\n+LINE2\n@@ -12,3 +12,3 @@\n line12\n line13\n-line14\n+LINE14\n"
		XCTAssertEqual(result.unifiedDiff, expected)
	}

	func testUnifiedDiffRewriteGolden() async throws {
		let original = "old\n"
		let request = makeRequest(mode: .rewrite(newText: "new\n", onMissing: .error), verbose: true)

		let result = try await engine.apply(request: request, to: original)
		let expected = "--- a/file.swift\n+++ b/file.swift\n@@ -1,1 +1,1 @@\n-old\n+new\n"
		XCTAssertEqual(result.unifiedDiff, expected)
	}
}



// MARK: - Merged from EscapeDecoderTests.swift


extension ApplyEditsCoreTests {
	func testDecodeModes() {
		struct Case {
			let name: String
			let mode: EscapeDecodingMode
			let input: String
			let expected: String
		}

		let cases: [Case] = [
			Case(name: "none_keeps_escapes", mode: .none, input: "a\\nb", expected: "a\\nb"),
			Case(name: "cStyle_decodes_newline", mode: .cStyle, input: "a\\nb", expected: "a\nb"),
			Case(name: "cStyle_decodes_tab", mode: .cStyle, input: "\\tindent", expected: "\tindent"),
			Case(name: "cStyle_decodes_quotes", mode: .cStyle, input: "\\\"q\\\"", expected: "\"q\""),
			Case(name: "smart_decodes_when_markers_present", mode: .smartHeuristic, input: "a\\nb", expected: "a\nb"),
			Case(name: "smart_does_not_decode_plain", mode: .smartHeuristic, input: "plain text", expected: "plain text")
		]

		let decoder = EscapeDecoder()
		for testCase in cases {
			let result = decoder.decode(testCase.input, mode: testCase.mode)
			XCTAssertEqual(result, testCase.expected, testCase.name)
		}
	}

	func testSmartHeuristicDecodesBackslashNInWindowsPath_likeString() {
		let input = "C:\\new\\file"
		let decoder = EscapeDecoder()
		let result = decoder.decode(input, mode: .smartHeuristic)

		XCTAssertNotEqual(result, input)
		XCTAssertTrue(result.contains("\n"))
	}
}
