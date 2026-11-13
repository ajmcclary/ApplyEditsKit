//
//  ApplyEditsMatchingAndFidelityTests.swift
//
//  Pins two contracts of `ApplyEditsEngine`:
//   • a search block is applied only where it verifiably occurs — literally,
//     or line by line when whitespace is ignored — and exactly once unless
//     replace_all is set; anything else fails with "not found"/ambiguity;
//   • the bytes written are the bytes the edit describes: untouched lines,
//     line endings, trailing whitespace, entities and backslashes survive.
//

import XCTest
@testable import ApplyEditsKit

final class ApplyEditsMatchingAndFidelityTests: XCTestCase {
	private let engine = ApplyEditsEngine.default

	private let accountFile = """
	import Foundation

	struct Account {
	    var balance: Int
	    var entries: [Int]

	    func describe() -> String {
	        return "Balance: \\(balance)"
	    }

	    func total() -> Int {
	        return entries.reduce(0, +)
	    }
	}

	"""

	private func single(
		_ search: String,
		_ replace: String,
		replaceAll: Bool = false,
		path: String = "Account.swift",
		in text: String
	) async throws -> ApplyEditsResult {
		try await engine.apply(
			request: ApplyEditsRequest(
				path: path,
				mode: .single(search: search, replace: replace, replaceAll: replaceAll),
				verbose: false
			),
			to: text
		)
	}

	private func rewrite(_ newText: String, path: String = "file.txt", in text: String) async throws -> ApplyEditsResult {
		try await engine.apply(
			request: ApplyEditsRequest(path: path, mode: .rewrite(newText: newText, onMissing: .error), verbose: false),
			to: text
		)
	}

	private func batch(_ edits: [ApplyEditsOperation], path: String = "file.txt", in text: String) async throws -> ApplyEditsResult {
		try await engine.apply(
			request: ApplyEditsRequest(path: path, mode: .batch(edits), verbose: true),
			to: text
		)
	}

	private func assertNotFound(
		_ search: String,
		in text: String,
		file: StaticString = #filePath,
		line: UInt = #line
	) async {
		await XCTAssertThrowsErrorAsync(
			try await self.single(search, "// GONE", in: text),
			file: file,
			line: line
		) { error in
			guard case ApplyEditsError.invalidParams(let message) = error else {
				return XCTFail("Expected invalidParams, got \(error)", file: file, line: line)
			}
			XCTAssertTrue(message.contains("not found"), "Unexpected message: \(message)", file: file, line: line)
		}
	}

	// MARK: - A search block that is not in the file fails

	func testSearchTextThatAppearsNowhereFailsAsNotFound() async {
		await assertNotFound("this text does not exist anywhere in the file", in: accountFile)
	}

	func testHallucinatedMultiLineBlockFailsAsNotFound() async {
		await assertNotFound("struct Wallet {\n    var coins: Int\n    func show() -> String {", in: accountFile)
	}

	func testTwoLineBlockWhoseSecondLineIsMissingFailsAsNotFound() async {
		await assertNotFound("    }\n    func doesNotExistAnywhere() {", in: accountFile)
	}

	func testOneLineNearMissFailsAsNotFound() async {
		await assertNotFound("        return entries.reduce(1, *)", in: accountFile)
	}

	func testStaleBlockWithChangedMiddleLinesFailsAsNotFound() async {
		// The user changed two lines in the middle of `describe` and `total`;
		// a six-line search computed from the old text must not overwrite them.
		let stale = """
		    func describe() -> String {
		        return "Old balance: \\(balance)"
		    }

		    func total() -> Int {
		        return entries.count
		"""
		await assertNotFound(stale, in: accountFile)
	}

	func testPlaceholderContentIsNeverMatchedByUnrelatedSearch() async {
		for placeholder in ["[File too large: 12345678 bytes]", "[Binary file]", "[Binary data or unknown encoding]"] {
			await assertNotFound("    let largeBuffer = makeBuffer()", in: placeholder)
		}
	}

	func testCaseOnlyDifferenceIsNotAMatch() async {
		await assertNotFound("STRUCT ACCOUNT {", in: accountFile)
	}

	func testBatchEditWithMissingSearchIsReportedFailed() async throws {
		let result = try await batch(
			[ApplyEditsOperation(search: "struct Wallet {\n    var coins: Int", replace: "X", replaceAll: false)],
			in: accountFile
		)
		XCTAssertEqual(result.status, .failed)
		XCTAssertEqual(result.updatedText, accountFile)
		XCTAssertEqual(result.outcomes?.first?.status, "failed")
	}

	func testNonLiteralBlockMatchingTwoPlacesIsAmbiguousEveryTime() async {
		let text = "func a() {\n    work()\n}\nfunc b() {\n\twork()\n}\n"
		for _ in 0..<20 {
			await XCTAssertThrowsErrorAsync(try await self.single("\t\twork()", "\t\trest()", in: text)) { error in
				guard case ApplyEditsError.invalidParams(let message) = error else {
					return XCTFail("Expected invalidParams, got \(error)")
				}
				XCTAssertTrue(message.contains("multiple locations"), message)
				XCTAssertTrue(message.contains("2") && message.contains("5"), message)
			}
		}
	}

	// MARK: - Legitimate whitespace leniency keeps working

	func testBlockWithTabIndentationMatchesSpaceIndentedFileAndKeepsFileStyle() async throws {
		let result = try await single(
			"\tfunc total() -> Int {\n\t\treturn entries.reduce(0, +)\n\t}",
			"\tfunc total() -> Int {\n\t\treturn entries.reduce(0, *)\n\t}",
			in: accountFile
		)
		XCTAssertEqual(result.status, .success)
		XCTAssertEqual(
			result.updatedText,
			accountFile.replacingOccurrences(of: "reduce(0, +)", with: "reduce(0, *)")
		)
	}

	func testBlockWithShallowerIndentationIsReindentedToTheFile() async throws {
		let result = try await single(
			"func total() -> Int {\n    return entries.reduce(0, +)\n}",
			"func total() -> Int {\n    let sum = entries.reduce(0, +)\n    return sum\n}",
			in: accountFile
		)
		XCTAssertEqual(
			result.updatedText,
			accountFile.replacingOccurrences(
				of: "        return entries.reduce(0, +)\n",
				with: "        let sum = entries.reduce(0, +)\n        return sum\n"
			)
		)
	}

	func testBlockWithNarrowerIndentUnitIsScaledToTheFile() async throws {
		let original = "class A {\n    func f() {\n        x()\n    }\n}\n"
		let result = try await single(
			"  func f() {\n    x()\n  }",
			"  func f() {\n    if y {\n      x()\n    }\n  }",
			in: original
		)
		XCTAssertEqual(
			result.updatedText,
			"class A {\n    func f() {\n        if y {\n            x()\n        }\n    }\n}\n"
		)
	}

	func testBlockDifferingOnlyInTrailingWhitespaceMatches() async throws {
		let result = try await single(
			"    var balance: Int   \n    var entries: [Int]\t",
			"    var balance: Double\n    var entries: [Int]",
			in: accountFile
		)
		XCTAssertEqual(
			result.updatedText,
			accountFile.replacingOccurrences(of: "var balance: Int", with: "var balance: Double")
		)
	}

	func testSearchWithCRLFMatchesLFFileAndKeepsFileEndings() async throws {
		let result = try await single(
			"  var balance: Int\r\n  var entries: [Int]",
			"  var balance: Double\r\n  var entries: [Int]",
			in: accountFile
		)
		XCTAssertEqual(
			result.updatedText,
			accountFile.replacingOccurrences(of: "var balance: Int", with: "var balance: Double")
		)
	}

	// MARK: - Leniency never changes the file's structure

	func testInnerWhitespaceIsNotLenient() async {
		await assertNotFound("    var balance:  Int", in: accountFile)
		await assertNotFound("\ts = \"a b\"", in: "s = \"a  b\"\n")
		await assertNotFound("\tx = 'a b'", in: "x = 'a\u{00A0}b'\n")
	}

	func testSearchWhoseNestingContradictsTheFileFailsAsNotFound() async {
		let python = "def f(x):\n    if x:\n        a()\n    b()\n"
		let cases: [(file: String, search: String, path: String)] = [
			(python, "if x:\na()", "m.py"),
			(python, "if x:\na()\nb()", "m.py"),
			("if x:\n    a()\nb()\n", "if x:\n    a()\n    b()", "m.py"),
			("a:\n  b: 1\nc: 2\n", "a:\nb: 1", "c.yaml"),
			("a:\n  b: 1\nc: 2\n", "a:\n  b: 1\n  c: 2", "c.yaml"),
		]
		for testCase in cases {
			await XCTAssertThrowsErrorAsync(
				try await self.single(testCase.search, "REPLACED", path: testCase.path, in: testCase.file)
			) { error in
				guard case ApplyEditsError.invalidParams(let message) = error else {
					return XCTFail("Expected invalidParams for \(testCase.search), got \(error)")
				}
				XCTAssertTrue(message.contains("not found"), message)
				XCTAssertTrue(message.contains("indentation"), message)
			}
		}
	}

	func testUniformlyShiftedPythonBlockIsReplacedAtTheFileIndentation() async throws {
		let python = "def f(x):\n    if x:\n        a()\n    b()\n"
		let result = try await single("if x:\n    a()", "if x:\n    c()\n    d()", path: "m.py", in: python)
		XCTAssertEqual(result.updatedText, "def f(x):\n    if x:\n        c()\n        d()\n    b()\n")
	}

	func testReplacementDeeperOrShallowerThanTheSearchIsRebasedByTheSameShift() async throws {
		let yaml = "root:\n  a:\n    b: 1\n  c: 2\n"
		let result = try await single("a:\n  b: 1", "a:\n  b: 1\n  sub:\n    deep: true\nz: 0", path: "c.yaml", in: yaml)
		XCTAssertEqual(result.updatedText, "root:\n  a:\n    b: 1\n    sub:\n      deep: true\n  z: 0\n  c: 2\n")
	}

	func testMatchIsChosenAmongCandidatesByIndentationStructure() async throws {
		// The lines "if x:" / "a()" occur twice; only one has the search's nesting.
		let python = "if x:\na()\nif x:\n    a()\n"
		let result = try await single("  if x:\n      a()", "  if x:\n      b()", path: "m.py", in: python)
		XCTAssertEqual(result.updatedText, "if x:\na()\nif x:\n    b()\n")
	}

	func testWhitespaceLenientResultIsDeterministic() async throws {
		var outputs = Set<String>()
		for _ in 0..<20 {
			let result = try await single(
				"\tvar entries: [Int]",
				"\tvar entries: [Int] = []",
				in: accountFile
			)
			outputs.insert(result.updatedText)
		}
		XCTAssertEqual(outputs.count, 1)
		XCTAssertEqual(outputs.first, accountFile.replacingOccurrences(of: "[Int]\n", with: "[Int] = []\n"))
	}

	func testEscapedLeadingTabSearchStillMatchesWhenTheFileHasNoBackslash() async throws {
		let result = try await single("\\tvar entries: [Int]", "\\tvar entries: [Int] = []", in: accountFile)
		XCTAssertEqual(result.updatedText, accountFile.replacingOccurrences(of: "[Int]\n", with: "[Int] = []\n"))
	}

	// MARK: - Bytes written are the bytes described

	func testRewriteWritesHTMLEntitiesVerbatim() async throws {
		let text = "<p>a &lt; b &amp;&amp; c &quot;q&quot; &nbsp;x</p>\n"
		let result = try await rewrite(text, path: "page.html", in: "<p>old</p>\n")
		XCTAssertEqual(result.updatedText, text)
	}

	func testWhitespaceLenientReplacementKeepsHTMLEntities() async throws {
		let original = "<ul>\n    <li>Fish and Chips</li>\n</ul>\n"
		let result = try await single(
			"\t<li>Fish and Chips</li>",
			"\t<li>Fish &amp; Chips</li>",
			path: "menu.html",
			in: original
		)
		XCTAssertEqual(result.updatedText, "<ul>\n    <li>Fish &amp; Chips</li>\n</ul>\n")
	}

	func testRewriteKeepsLeadingBackslashT() async throws {
		let text = "\\tau = 1\n\\times 2\n\\temp\\x\n"
		let result = try await rewrite(text, path: "a.md", in: "old\n")
		XCTAssertEqual(result.updatedText, text)
	}

	func testWhitespaceLenientReplacementKeepsLeadingBackslashT() async throws {
		let original = "Intro\n    $x$ value\nOutro\n"
		let result = try await single("\t$x$ value", "\t\\theta = 1", path: "notes.md", in: original)
		XCTAssertEqual(result.updatedText, "Intro\n    \\theta = 1\nOutro\n")
	}

	func testOneTabLineDoesNotConvertEditedSpaceIndentationToTabs() async throws {
		let yaml = "root:\n  a:\n    b: 1\n\tlegacy: true\n  c: 2\n"
		let result = try await single("    b: 1", "    b: 10\n      nested: true", path: "c.yaml", in: yaml)
		XCTAssertEqual(result.updatedText, "root:\n  a:\n    b: 10\n      nested: true\n\tlegacy: true\n  c: 2\n")
	}

	func testLiteralEditKeepsTrailingSpaces() async throws {
		let original = "line one\nline two  \nline three\n"
		let result = try await single("line two  \n", "line 2  \nextra  \n", path: "doc.md", in: original)
		XCTAssertEqual(result.updatedText, "line one\nline 2  \nextra  \nline three\n")
	}

	func testRewriteIsWrittenVerbatim() async throws {
		let original = "def f():\n    return 1\n"
		let cases: [(String, String)] = [
			(original, "def f():  \n\treturn 2"),
			("a\nb", "a\nb\nc\n"),
			(original, ""),
			("a\r\nb\r\n", "x\ny\n"),
		]
		for (before, after) in cases {
			let result = try await rewrite(after, path: "f.py", in: before)
			XCTAssertEqual(result.updatedText, after)
		}
	}

	func testEditKeepsMixedLineEndingsOfUntouchedLines() async throws {
		let original = "a\nb\r\nc\nd\n"
		let literal = try await single("c", "C", path: "f.txt", in: original)
		XCTAssertEqual(literal.updatedText, "a\nb\r\nC\nd\n")

		let lenient = try await single("  c", "C", path: "f.txt", in: original)
		XCTAssertEqual(lenient.updatedText, "a\nb\r\nC\nd\n")
	}

	func testEditKeepsEverythingAfterANULCharacter() async throws {
		let original = "a\nb\nc\0d\ne\nf\n"
		let result = try await single("b", "B", path: "f.txt", in: original)
		XCTAssertEqual(result.updatedText, "a\nB\nc\0d\ne\nf\n")

		let lenient = try await single("  e", "E", path: "f.txt", in: original)
		XCTAssertEqual(lenient.updatedText, "a\nb\nc\0d\nE\nf\n")
	}

	// MARK: - No-op and whitespace-only edits succeed

	func testWhitespaceOnlyAndNoOpEditsSucceed() async throws {
		let removeTrailing = try await single("a   \n", "a\n", path: "f.txt", in: "a   \nb\n")
		XCTAssertEqual(removeTrailing.updatedText, "a\nb\n")

		let tabToSpaces = try await single("\tb", "    b", path: "f.txt", in: "a\n\tb\n")
		XCTAssertEqual(tabToSpaces.updatedText, "a\n    b\n")

		let identical = try await rewrite("same\n", in: "same\n")
		XCTAssertEqual(identical.status, .success)
		XCTAssertEqual(identical.updatedText, "same\n")

		let addFinalNewline = try await rewrite("x\ny\n", in: "x\ny")
		XCTAssertEqual(addFinalNewline.updatedText, "x\ny\n")
	}

	// MARK: - Batches

	func testBatchReplaceAllDoesNotDestroyUnrelatedLines() async throws {
		let original = "foo()\nalpha\nbeta\nfoo()\ngamma\ndelta\n"
		let result = try await batch(
			[
				ApplyEditsOperation(search: "foo()", replace: "X()", replaceAll: true),
				ApplyEditsOperation(search: "DELTA", replace: "finish", replaceAll: false),
			],
			in: original
		)
		XCTAssertEqual(result.updatedText, "X()\nalpha\nbeta\nX()\ngamma\ndelta\n")
		XCTAssertEqual(result.status, .partial)
		XCTAssertEqual(result.outcomes?.map(\.status), ["success", "failed"])
	}

	func testBatchMultiLineReplaceAllKeepsSurroundingLines() async throws {
		let original = "keep1\nA\nB\nkeep2\nkeep3\nA\nB\nkeep4\nkeep5\nA\nB\nkeep6\nkeep7\nkeep8\nlast\n"
		let result = try await batch(
			[
				ApplyEditsOperation(search: "A\nB", replace: "AB", replaceAll: true),
				ApplyEditsOperation(search: "  last", replace: "finish", replaceAll: false),
			],
			in: original
		)
		XCTAssertEqual(
			result.updatedText,
			"keep1\nAB\nkeep2\nkeep3\nAB\nkeep4\nkeep5\nAB\nkeep6\nkeep7\nkeep8\nfinish\n"
		)
		XCTAssertEqual(result.status, .success)
	}

	func testBatchEditsApplyInOrderAndAnEditWhoseTextWasConsumedFails() async throws {
		let original = "l1\nl2\nl3\nl4\nl5\nl6\n"
		let result = try await batch(
			[
				ApplyEditsOperation(search: "l2\nl3", replace: "L2\nL3\nL3b", replaceAll: false),
				ApplyEditsOperation(search: "l3\nl4", replace: "M3\nM4", replaceAll: false),
			],
			in: original
		)
		XCTAssertEqual(result.updatedText, "l1\nL2\nL3\nL3b\nl4\nl5\nl6\n")
		XCTAssertEqual(result.status, .partial)
		XCTAssertEqual(result.outcomes?.map(\.status), ["success", "failed"])
	}

	func testBatchIdenticalSearchesConsumeSuccessiveOccurrences() async throws {
		let original = "x\nvalue = 1\ny\nvalue = 1\nz\n"
		let result = try await batch(
			[
				ApplyEditsOperation(search: "value = 1", replace: "value = 1 // first", replaceAll: false),
				ApplyEditsOperation(search: "value = 1", replace: "value = 2", replaceAll: false),
			],
			in: original
		)
		XCTAssertEqual(result.status, .success)
		XCTAssertEqual(result.updatedText, "x\nvalue = 1 // first\ny\nvalue = 2\nz\n")
	}

	func testBatchWithLenientEditKeepsBytesOfOtherLines() async throws {
		let original = "a  \nb\r\n\tc\nd\n"
		let result = try await batch(
			[
				ApplyEditsOperation(search: "  c", replace: "  C", replaceAll: false),
				ApplyEditsOperation(search: "d", replace: "D", replaceAll: false),
			],
			in: original
		)
		XCTAssertEqual(result.updatedText, "a  \nb\r\n\tC\nD\n")
		XCTAssertEqual(result.status, .success)
	}
}

// MARK: - Edge cases of the lenient path and the chunk applier

extension ApplyEditsMatchingAndFidelityTests {
	func testLenientDeletionOfTheLastLinesDoesNotAddAFinalNewline() async throws {
		let result = try await single("  b\n  c", "", path: "f.txt", in: "a\nb\nc")
		XCTAssertEqual(result.updatedText, "a")
	}

	func testLenientDeletionInTheMiddleRemovesWholeLines() async throws {
		let result = try await single("\tb", "", path: "f.txt", in: "a\r\nb\r\nc\r\n")
		XCTAssertEqual(result.updatedText, "a\r\nc\r\n")
	}

	func testLenientReplaceAllReplacesEveryVerifiedBlock() async throws {
		let original = "if x {\n    go()\n}\nfunc f() {\n    if y {\n        go()\n    }\n}\n"
		let result = try await single("\tgo()", "\tstop()", replaceAll: true, path: "f.swift", in: original)
		XCTAssertEqual(result.updatedText, "if x {\n    stop()\n}\nfunc f() {\n    if y {\n        stop()\n    }\n}\n")
	}

	func testWhitespaceOnlySearchThatIsNotLiteralFailsAsNotFound() async {
		await assertNotFound("   \n\t", in: "a\nb\n")
	}

	func testChunkApplierRejectsChunksThatDoNotMatchTheFile() {
		let applier = DefaultDiffChunkApplier()
		let mismatched = DiffChunk(lines: [DiffLine(content: "-<s0>zzz"), DiffLine(content: "+<s0>new")], startLine: 1)
		XCTAssertThrowsError(try applier.apply(chunks: [mismatched], to: "a\nb\nc\n", fileAction: .modify))

		let first = DiffChunk(lines: [DiffLine(content: "-<s0>b"), DiffLine(content: "-<s0>c")], startLine: 1)
		let overlapping = DiffChunk(lines: [DiffLine(content: "-<s0>c")], startLine: 2)
		XCTAssertThrowsError(try applier.apply(chunks: [first, overlapping], to: "a\nb\nc\n", fileAction: .modify))

		let pastEnd = DiffChunk(lines: [DiffLine(content: " <s0>c"), DiffLine(content: "-<s0>d")], startLine: 2)
		XCTAssertThrowsError(try applier.apply(chunks: [pastEnd], to: "a\nb\nc\n", fileAction: .modify))
	}

	func testChunkApplierKeepsUntouchedBytesAndUsesOriginalCoordinates() throws {
		let applier = DefaultDiffChunkApplier()
		let original = "a  \nb\r\nc\nd\ne\n"
		let chunks = [
			DiffChunk(lines: [DiffLine(content: "-<s0>b"), DiffLine(content: "+<s0>B1"), DiffLine(content: "+<s0>B2")], startLine: 1),
			DiffChunk(lines: [DiffLine(content: " <s0>d"), DiffLine(content: "-<s0>e")], startLine: 3),
		]
		XCTAssertEqual(try applier.apply(chunks: chunks, to: original, fileAction: .modify), "a  \nB1\nB2\nc\nd\n")
		XCTAssertEqual(try applier.apply(chunks: [], to: original, fileAction: .modify), original)
	}
}

// MARK: - Service

extension ApplyEditsMatchingAndFidelityTests {
	private actor ChangingHost: FileEditHost {
		private var reads = 0
		private(set) var writes: [String] = []
		func fileExists(path: String) async -> Bool { true }
		func readText(path: String) async throws -> String {
			reads += 1
			return reads == 1 ? "Hello\n" : "Hello\nuser edit\n"
		}
		func writeText(path: String, content: String, overwrite: Bool) async throws {
			writes.append(content)
		}
	}

	func testServiceDoesNotOverwriteAFileThatChangedAfterItWasRead() async throws {
		let host = ChangingHost()
		let service = ApplyEditsService(engine: .default, host: host)
		let request = ApplyEditsRequest(
			path: "file.swift",
			mode: .single(search: "Hello", replace: "Hi", replaceAll: false),
			verbose: false
		)
		await XCTAssertThrowsErrorAsync(try await service.run(request)) { error in
			XCTAssertEqual(error as? ApplyEditsFileChangedError, ApplyEditsFileChangedError(path: "file.swift", reason: .contentChanged))
			XCTAssertTrue((error as? LocalizedError)?.errorDescription?.contains("changed") == true)
		}
		let writes = await host.writes
		XCTAssertTrue(writes.isEmpty)
	}
}

// MARK: - Prepare, then commit

extension ApplyEditsMatchingAndFidelityTests {
	private func singleRequest(_ search: String, _ replace: String, path: String = "file.swift") -> ApplyEditsRequest {
		ApplyEditsRequest(path: path, mode: .single(search: search, replace: replace, replaceAll: false), verbose: false)
	}

	func testPreparedEditCarriesTheIdentityOfItsBaseAndCommitWritesIt() async throws {
		let host = InMemoryFileEditHost(files: ["file.swift": "Hello\n"])
		let service = ApplyEditsService(engine: .default, host: host)

		let prepared = try await service.prepare(singleRequest("Hello", "Hi"))
		XCTAssertEqual(prepared.path, "file.swift")
		XCTAssertEqual(prepared.base, ApplyEditsBaseIdentity(text: "Hello\n"))
		XCTAssertNotEqual(prepared.base, ApplyEditsBaseIdentity(text: "Hello\r\n"))
		XCTAssertEqual(prepared.result.updatedText, "Hi\n")
		let writesBeforeCommit = await host.writes
		XCTAssertTrue(writesBeforeCommit.isEmpty)

		let committed = try await service.commit(prepared)
		XCTAssertEqual(committed.status, .success)
		XCTAssertFalse(committed.fileCreated)
		let stored = await host.currentText(path: "file.swift")
		XCTAssertEqual(stored, "Hi\n")
	}

	func testCommitRefusesWhenTheFileChangedSincePreview() async throws {
		let host = InMemoryFileEditHost(files: ["file.swift": "Hello\n"])
		let service = ApplyEditsService(engine: .default, host: host)
		let prepared = try await service.prepare(singleRequest("Hello", "Hi"))

		await host.setText(path: "file.swift", text: "Hello\nuser line\n")
		await XCTAssertThrowsErrorAsync(try await service.commit(prepared)) { error in
			XCTAssertEqual(error as? ApplyEditsFileChangedError, ApplyEditsFileChangedError(path: "file.swift", reason: .contentChanged))
		}

		await host.setText(path: "file.swift", text: nil)
		await XCTAssertThrowsErrorAsync(try await service.commit(prepared)) { error in
			XCTAssertEqual(error as? ApplyEditsFileChangedError, ApplyEditsFileChangedError(path: "file.swift", reason: .fileDeleted))
		}
		let writes = await host.writes
		XCTAssertTrue(writes.isEmpty)
	}

	func testCommitOfACreateRefusesWhenTheFileAppearedSincePreview() async throws {
		let host = InMemoryFileEditHost()
		let service = ApplyEditsService(engine: .default, host: host)
		let prepared = try await service.prepare(
			ApplyEditsRequest(path: "new.swift", mode: .rewrite(newText: "new\n", onMissing: .create), verbose: false)
		)
		XCTAssertNil(prepared.base)

		await host.setText(path: "new.swift", text: "someone else\n")
		await XCTAssertThrowsErrorAsync(try await service.commit(prepared)) { error in
			XCTAssertEqual(error as? ApplyEditsFileChangedError, ApplyEditsFileChangedError(path: "new.swift", reason: .fileCreated))
		}
		let stored = await host.currentText(path: "new.swift")
		XCTAssertEqual(stored, "someone else\n")

		await host.setText(path: "new.swift", text: nil)
		let created = try await service.commit(prepared)
		XCTAssertTrue(created.fileCreated)
		let written = await host.currentText(path: "new.swift")
		XCTAssertEqual(written, "new\n")
	}

	func testCommitOfAnEditThatAppliedNothingWritesNothing() async throws {
		let host = InMemoryFileEditHost(files: ["file.swift": "One\n"])
		let service = ApplyEditsService(engine: .default, host: host)
		let prepared = try await service.prepare(
			ApplyEditsRequest(path: "file.swift", mode: .batch([ApplyEditsOperation(search: "Missing", replace: "X", replaceAll: false)]), verbose: false)
		)
		await host.setText(path: "file.swift", text: "changed\n")
		let result = try await service.commit(prepared)
		XCTAssertEqual(result.status, .failed)
		let writes = await host.writes
		XCTAssertTrue(writes.isEmpty)
	}
}

// MARK: - The display diff shows every change that is written

extension ApplyEditsMatchingAndFidelityTests {
	private func verboseSingle(_ search: String, _ replace: String, in text: String) async throws -> ApplyEditsResult {
		try await engine.apply(
			request: ApplyEditsRequest(path: "f.txt", mode: .single(search: search, replace: replace, replaceAll: false), verbose: true),
			to: text
		)
	}

	func testTrailingWhitespaceRemovalIsShownInTheDiff() async throws {
		let result = try await verboseSingle("a   \n", "a\n", in: "a   \nb\n")
		XCTAssertFalse(result.diffChunks.isEmpty)
		XCTAssertEqual(result.stats?.linesChanged, 1)
		XCTAssertTrue(result.toolCardUnifiedDiff?.contains("-a   \n+a\n") == true, result.toolCardUnifiedDiff ?? "nil")
		XCTAssertTrue(result.unifiedDiff?.contains("-a   \n+a\n") == true, result.unifiedDiff ?? "nil")
	}

	func testTabToSpacesIsShownInTheDiff() async throws {
		let result = try await verboseSingle("\tb", "    b", in: "a\n\tb\n")
		XCTAssertEqual(result.stats?.linesChanged, 1)
		XCTAssertTrue(result.toolCardUnifiedDiff?.contains("-\tb\n+    b\n") == true, result.toolCardUnifiedDiff ?? "nil")
	}

	func testLineEndingOnlyRewriteIsShownAndExplained() async throws {
		let result = try await engine.apply(
			request: ApplyEditsRequest(path: "f.txt", mode: .rewrite(newText: "x\ny\n", onMissing: .error), verbose: true),
			to: "x\r\ny\r\n"
		)
		XCTAssertEqual(result.stats?.linesChanged, 2)
		XCTAssertNotNil(result.toolCardUnifiedDiff)
		XCTAssertTrue(result.note?.contains("line endings") == true, result.note ?? "nil")
	}

	func testAddingAFinalNewlineIsShownInTheDiff() async throws {
		let result = try await engine.apply(
			request: ApplyEditsRequest(path: "f.txt", mode: .rewrite(newText: "x\ny\n", onMissing: .error), verbose: true),
			to: "x\ny"
		)
		XCTAssertEqual(result.stats?.linesChanged, 1)
		XCTAssertNotNil(result.toolCardUnifiedDiff)
	}

	func testVerboseDiffOfALineWithNULIsNotTruncated() async throws {
		let result = try await verboseSingle("a\0b", "a\0B", in: "a\0b\n")
		XCTAssertTrue(result.unifiedDiff?.contains("+a\0B") == true, result.unifiedDiff ?? "nil")
	}

	func testEditInAMixedEndingFileShowsOnlyTheChangedLine() async throws {
		let result = try await verboseSingle("c", "C", in: "a\nb\r\nc\nd\r\n")
		XCTAssertEqual(result.stats?.linesChanged, 1)
		XCTAssertNil(result.note)
	}
}
