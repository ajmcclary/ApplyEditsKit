import XCTest
import ApplyEditsKit

/// Public-API boundary contract for ApplyEditsKit (the third migrate.md
/// extraction). The deep behavior pins live in the suites that moved with
/// the code; this file pins two things those suites cannot: (1) every
/// vocabulary family RepoPrompt consumes stays PUBLIC — this file
/// deliberately imports WITHOUT `@testable`, so any accidental
/// de-publicizing breaks compilation — and (2) the raw-value and
/// coding-key formats that cross the package boundary as persisted or
/// wire identity (FileChange payloads in saved agent sessions, FileAction
/// and status strings in tool results), plus the ApplyEditsCSupport C
/// bridge staying linked through the public String surface (including the
/// four repo_* similarity symbols WorkspaceKitCSupport defines).
final class ApplyEditsKitPublicAPIContractTests: XCTestCase {
	// Compile-time public-visibility pins, one alias per vocabulary family.
	// A tuple type references each member type without needing constructible
	// values; removal or de-publicizing of any member is a compile error.
	private typealias EngineFamily = (ApplyEditsEngine, ApplyEditsService, ApplyEditsEscapeFallback, DefaultDiffChunkGenerator, DefaultDiffChunkApplier, DefaultUnifiedDiffRenderer)
	private typealias PortFamily = (FileEditHost, DiffChunkGenerator, DiffChunkApplier, UnifiedDiffRendering)
	private typealias RequestFamily = (ApplyEditsMode, ApplyEditsOperation, OnMissing, ApplyEditsRequest, ApplyEditsExecutionOptions, ApplyEditsError)
	private typealias ResultFamily = (ApplyEditsStatus, ApplyEditsStats, ApplyEditsLineStats, ApplyEditsResult, EditOutcome, Edit)
	private typealias DiffingFamily = (DiffChunk, DiffLine, DiffApplicator, DiffApplicationError, EditOperation, DiffGenerationUtility, DiffGenerationError, DiffPrecision, DiffBatchGenerator, DiffParserUtils, UnifiedDiffGenerator, DiffEncodingUtils, DiffEdit, DiffEditCreator, DiffEditCursor)
	private typealias ChangeFamily = (FileChange, FileAction, ChangeManager, ChangeApplier, ChangeGroup, ChangeApplicationError)
	private typealias UtilityFamily = (EscapeDecodingMode, EscapeDecoder, IndentationConfig, IndentCorrectionUtility, OptimalLineFinderUtility, EditFlowPerf)

	func testFileActionRawValuesStable() {
		// Persisted in saved agent-session payloads and tool routing.
		XCTAssertEqual(FileAction.modify.rawValue, "modify")
		XCTAssertEqual(FileAction.create.rawValue, "create")
		XCTAssertEqual(FileAction.delete.rawValue, "delete")
		XCTAssertEqual(FileAction.rewrite.rawValue, "rewrite")
		XCTAssertEqual(FileAction.delegateEdit.rawValue, "delegateEdit")
	}

	func testStatusAndOnMissingRawValuesStable() {
		// status.rawValue crosses into MCP tool results (MCPServerViewModel).
		XCTAssertEqual(ApplyEditsStatus.success.rawValue, "success")
		XCTAssertEqual(ApplyEditsStatus.partial.rawValue, "partial")
		XCTAssertEqual(ApplyEditsStatus.failed.rawValue, "failed")
		XCTAssertEqual(OnMissing.error.rawValue, "error")
		XCTAssertEqual(OnMissing.create.rawValue, "create")
	}

	func testFileChangePersistedCodingKeysStable() throws {
		let change = FileChange(
			startLine: 3,
			description: "swap greeting",
			diffChunk: DiffChunk(lines: [DiffLine(content: "-old"), DiffLine(content: "+new")], startLine: 3)
		)
		let data = try JSONEncoder().encode(change)
		let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		XCTAssertEqual(Set(object.keys), ["start_line", "description", "chunk"])
		let decoded = try JSONDecoder().decode(FileChange.self, from: data)
		XCTAssertEqual(decoded.startLine, 3)
		XCTAssertEqual(decoded.description, "swap greeting")
		XCTAssertEqual(decoded.diffChunk.lines.map(\.rawContent), ["-old", "+new"])
	}

	func testExecutionOptionPresetsStable() {
		XCTAssertTrue(ApplyEditsExecutionOptions.default.includeToolCardUnifiedDiff)
		XCTAssertFalse(ApplyEditsExecutionOptions.delegateSandbox.includeToolCardUnifiedDiff)
	}

	func testCSupportBridgeLinksThroughPublicStringSurface() {
		// WorkspaceKitCSupport-defined symbols (repo_levenshtein_distance /
		// repo_similarity_score) reachable through the product dependency:
		XCTAssertEqual("kitten".levenshteinDistance(to: "sitting"), 3)
		XCTAssertEqual("same".similarity(to: "same"), 1.0, accuracy: 0.0001)
		// ApplyEditsCSupport-defined symbols (repo_escape_string /
		// repo_unescape_string / repo_fnv1a64):
		XCTAssertEqual("a\\nb".unescaped(), "a\nb")
		XCTAssertEqual("x".fnv1a64(), "x".fnv1a64())
		XCTAssertNotEqual("x".fnv1a64(), "y".fnv1a64())
	}
}
