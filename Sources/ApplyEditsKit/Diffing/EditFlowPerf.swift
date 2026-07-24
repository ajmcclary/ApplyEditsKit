import Foundation
#if DEBUG || EDIT_FLOW_PERF
import os
#endif

/// Lightweight, gated instrumentation for apply_edits / delegate edit hot paths.
///
/// Keep this utility safe for broad use:
/// - disabled by default and cheap on the fast path;
/// - stage names are static;
/// - dimensions are coarse counts/status labels only;
/// - never pass raw paths, patterns, replacement text, file content, or diffs.
public enum EditFlowPerf {
	#if DEBUG || EDIT_FLOW_PERF
	public typealias IntervalState = OSSignpostIntervalState
	#else
	public struct IntervalState: Sendable {}
	#endif

	public struct Dimensions: Sendable {
		public var toolName: String?
		public var runPurpose: String?
		public var status: String?
		public var outcome: String?
		public var fileBytes: Int?
		public var lineCount: Int?
		public var diffLines: Int?
		public var editCount: Int?
		public var matchCount: Int?
		public var appliedCount: Int?
		public var chunkCount: Int?
		public var taskCount: Int?
		public var activeCount: Int?
		public var isError: Bool?
		public var isForced: Bool?
		public var isAgentMode: Bool?
		public var includesToolCardDiff: Bool?
		public var searchMode: String?
		public var scanKind: String?
		public var fileCount: Int?
		public var batchSize: Int?
		public var maxResults: Int?
		public var cacheHit: Bool?
		public var isRegex: Bool?
		public var countOnly: Bool?
		public var caseInsensitive: Bool?
		public var wholeWord: Bool?
		public var contextLines: Int?
		public var sourceItemCount: Int?
		public var sanitizedActivityCount: Int?
		public var retainedPayloadCount: Int?
		public var retainedPayloadBytes: Int?
		public var jsonParseAttemptCount: Int?
		public var jsonParseCacheHitCount: Int?
		public var jsonParseCacheMissCount: Int?
		public var jsonParseSuccessCount: Int?
		public var jsonParseFailureCount: Int?
		public var jsonParseByteCount: Int?
		public var toolExecutionCacheHitCount: Int?
		public var toolExecutionCacheMissCount: Int?
		public var bashMetadataCacheHitCount: Int?
		public var bashMetadataCacheMissCount: Int?
		public var regexCaptureCallCount: Int?
		public var inputBytes: Int?
		public var contentItemCount: Int?
		public var delegateEditCount: Int?
		public var changeCount: Int?
		public var scopeCount: Int?
		public var warningCount: Int?
		public var fileAction: String?

		public init(
			toolName: String? = nil,
			runPurpose: String? = nil,
			status: String? = nil,
			outcome: String? = nil,
			fileBytes: Int? = nil,
			lineCount: Int? = nil,
			diffLines: Int? = nil,
			editCount: Int? = nil,
			matchCount: Int? = nil,
			appliedCount: Int? = nil,
			chunkCount: Int? = nil,
			taskCount: Int? = nil,
			activeCount: Int? = nil,
			isError: Bool? = nil,
			isForced: Bool? = nil,
			isAgentMode: Bool? = nil,
			includesToolCardDiff: Bool? = nil,
			searchMode: String? = nil,
			scanKind: String? = nil,
			fileCount: Int? = nil,
			batchSize: Int? = nil,
			maxResults: Int? = nil,
			cacheHit: Bool? = nil,
			isRegex: Bool? = nil,
			countOnly: Bool? = nil,
			caseInsensitive: Bool? = nil,
			wholeWord: Bool? = nil,
			contextLines: Int? = nil,
			sourceItemCount: Int? = nil,
			sanitizedActivityCount: Int? = nil,
			retainedPayloadCount: Int? = nil,
			retainedPayloadBytes: Int? = nil,
			jsonParseAttemptCount: Int? = nil,
			jsonParseCacheHitCount: Int? = nil,
			jsonParseCacheMissCount: Int? = nil,
			jsonParseSuccessCount: Int? = nil,
			jsonParseFailureCount: Int? = nil,
			jsonParseByteCount: Int? = nil,
			toolExecutionCacheHitCount: Int? = nil,
			toolExecutionCacheMissCount: Int? = nil,
			bashMetadataCacheHitCount: Int? = nil,
			bashMetadataCacheMissCount: Int? = nil,
			regexCaptureCallCount: Int? = nil,
			inputBytes: Int? = nil,
			contentItemCount: Int? = nil,
			delegateEditCount: Int? = nil,
			changeCount: Int? = nil,
			scopeCount: Int? = nil,
			warningCount: Int? = nil,
			fileAction: String? = nil
		) {
			self.toolName = Self.sanitizedLabel(toolName)
			self.runPurpose = Self.sanitizedLabel(runPurpose)
			self.status = Self.sanitizedLabel(status)
			self.outcome = Self.sanitizedLabel(outcome)
			self.fileBytes = Self.nonNegative(fileBytes)
			self.lineCount = Self.nonNegative(lineCount)
			self.diffLines = Self.nonNegative(diffLines)
			self.editCount = Self.nonNegative(editCount)
			self.matchCount = Self.nonNegative(matchCount)
			self.appliedCount = Self.nonNegative(appliedCount)
			self.chunkCount = Self.nonNegative(chunkCount)
			self.taskCount = Self.nonNegative(taskCount)
			self.activeCount = Self.nonNegative(activeCount)
			self.isError = isError
			self.isForced = isForced
			self.isAgentMode = isAgentMode
			self.includesToolCardDiff = includesToolCardDiff
			self.searchMode = Self.sanitizedLabel(searchMode)
			self.scanKind = Self.sanitizedLabel(scanKind)
			self.fileCount = Self.nonNegative(fileCount)
			self.batchSize = Self.nonNegative(batchSize)
			self.maxResults = Self.nonNegative(maxResults)
			self.cacheHit = cacheHit
			self.isRegex = isRegex
			self.countOnly = countOnly
			self.caseInsensitive = caseInsensitive
			self.wholeWord = wholeWord
			self.contextLines = Self.nonNegative(contextLines)
			self.sourceItemCount = Self.nonNegative(sourceItemCount)
			self.sanitizedActivityCount = Self.nonNegative(sanitizedActivityCount)
			self.retainedPayloadCount = Self.nonNegative(retainedPayloadCount)
			self.retainedPayloadBytes = Self.nonNegative(retainedPayloadBytes)
			self.jsonParseAttemptCount = Self.nonNegative(jsonParseAttemptCount)
			self.jsonParseCacheHitCount = Self.nonNegative(jsonParseCacheHitCount)
			self.jsonParseCacheMissCount = Self.nonNegative(jsonParseCacheMissCount)
			self.jsonParseSuccessCount = Self.nonNegative(jsonParseSuccessCount)
			self.jsonParseFailureCount = Self.nonNegative(jsonParseFailureCount)
			self.jsonParseByteCount = Self.nonNegative(jsonParseByteCount)
			self.toolExecutionCacheHitCount = Self.nonNegative(toolExecutionCacheHitCount)
			self.toolExecutionCacheMissCount = Self.nonNegative(toolExecutionCacheMissCount)
			self.bashMetadataCacheHitCount = Self.nonNegative(bashMetadataCacheHitCount)
			self.bashMetadataCacheMissCount = Self.nonNegative(bashMetadataCacheMissCount)
			self.regexCaptureCallCount = Self.nonNegative(regexCaptureCallCount)
			self.inputBytes = Self.nonNegative(inputBytes)
			self.contentItemCount = Self.nonNegative(contentItemCount)
			self.delegateEditCount = Self.nonNegative(delegateEditCount)
			self.changeCount = Self.nonNegative(changeCount)
			self.scopeCount = Self.nonNegative(scopeCount)
			self.warningCount = Self.nonNegative(warningCount)
			self.fileAction = Self.sanitizedLabel(fileAction)
		}

		fileprivate var logDescription: String {
			var parts: [String] = []
			append("tool", toolName, to: &parts)
			append("purpose", runPurpose, to: &parts)
			append("status", status, to: &parts)
			append("outcome", outcome, to: &parts)
			append("fileBytes", fileBytes, to: &parts)
			append("lineCount", lineCount, to: &parts)
			append("diffLines", diffLines, to: &parts)
			append("editCount", editCount, to: &parts)
			append("matchCount", matchCount, to: &parts)
			append("appliedCount", appliedCount, to: &parts)
			append("chunkCount", chunkCount, to: &parts)
			append("taskCount", taskCount, to: &parts)
			append("activeCount", activeCount, to: &parts)
			append("isError", isError, to: &parts)
			append("isForced", isForced, to: &parts)
			append("isAgentMode", isAgentMode, to: &parts)
			append("includesToolCardDiff", includesToolCardDiff, to: &parts)
			append("searchMode", searchMode, to: &parts)
			append("scanKind", scanKind, to: &parts)
			append("fileCount", fileCount, to: &parts)
			append("batchSize", batchSize, to: &parts)
			append("maxResults", maxResults, to: &parts)
			append("cacheHit", cacheHit, to: &parts)
			append("isRegex", isRegex, to: &parts)
			append("countOnly", countOnly, to: &parts)
			append("caseInsensitive", caseInsensitive, to: &parts)
			append("wholeWord", wholeWord, to: &parts)
			append("contextLines", contextLines, to: &parts)
			append("sourceItemCount", sourceItemCount, to: &parts)
			append("sanitizedActivityCount", sanitizedActivityCount, to: &parts)
			append("retainedPayloadCount", retainedPayloadCount, to: &parts)
			append("retainedPayloadBytes", retainedPayloadBytes, to: &parts)
			append("jsonParseAttemptCount", jsonParseAttemptCount, to: &parts)
			append("jsonParseCacheHitCount", jsonParseCacheHitCount, to: &parts)
			append("jsonParseCacheMissCount", jsonParseCacheMissCount, to: &parts)
			append("jsonParseSuccessCount", jsonParseSuccessCount, to: &parts)
			append("jsonParseFailureCount", jsonParseFailureCount, to: &parts)
			append("jsonParseByteCount", jsonParseByteCount, to: &parts)
			append("toolExecutionCacheHitCount", toolExecutionCacheHitCount, to: &parts)
			append("toolExecutionCacheMissCount", toolExecutionCacheMissCount, to: &parts)
			append("bashMetadataCacheHitCount", bashMetadataCacheHitCount, to: &parts)
			append("bashMetadataCacheMissCount", bashMetadataCacheMissCount, to: &parts)
			append("regexCaptureCallCount", regexCaptureCallCount, to: &parts)
			append("inputBytes", inputBytes, to: &parts)
			append("contentItemCount", contentItemCount, to: &parts)
			append("delegateEditCount", delegateEditCount, to: &parts)
			append("changeCount", changeCount, to: &parts)
			append("scopeCount", scopeCount, to: &parts)
			append("warningCount", warningCount, to: &parts)
			append("fileAction", fileAction, to: &parts)
			return parts.joined(separator: " ")
		}

		fileprivate var isEmpty: Bool {
			logDescription.isEmpty
		}

		private static func nonNegative(_ value: Int?) -> Int? {
			value.map { max(0, $0) }
		}

		private static func sanitizedLabel(_ value: String?) -> String? {
			guard let value else { return nil }
			let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty else { return nil }
			let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
			let replacement = UnicodeScalar("_")
			let scalars = trimmed.unicodeScalars.map { scalar in
				allowed.contains(scalar) ? scalar : replacement
			}
			return String(String.UnicodeScalarView(scalars.prefix(64)))
		}

		private func append(_ key: String, _ value: String?, to parts: inout [String]) {
			guard let value else { return }
			parts.append("\(key)=\(value)")
		}

		private func append(_ key: String, _ value: Int?, to parts: inout [String]) {
			guard let value else { return }
			parts.append("\(key)=\(value)")
		}

		private func append(_ key: String, _ value: Bool?, to parts: inout [String]) {
			guard let value else { return }
			parts.append("\(key)=\(value ? "true" : "false")")
		}
	}

	public enum Stage {
		public enum MCPToolCall {
			public static let total: StaticString = "EditFlow.MCPToolCall.Total"
			public static let normalizeArgs: StaticString = "EditFlow.MCPToolCall.NormalizeArgs"
			public static let delegateSandboxIntercept: StaticString = "EditFlow.MCPToolCall.DelegateSandboxIntercept"
			public static let logicalContextResolution: StaticString = "EditFlow.MCPToolCall.LogicalContextResolution"
			public static let policyGating: StaticString = "EditFlow.MCPToolCall.PolicyGating"
			public static let observerCallbacks: StaticString = "EditFlow.MCPToolCall.ObserverCallbacks"
			public static let dispatch: StaticString = "EditFlow.MCPToolCall.Dispatch"
		}

		public enum ApplyEdits {
			public static let serviceRun: StaticString = "EditFlow.ApplyEdits.ServiceRun"
			public static let servicePreview: StaticString = "EditFlow.ApplyEdits.ServicePreview"
			public static let requestBuild: StaticString = "EditFlow.ApplyEdits.RequestBuild"
			public static let hostRead: StaticString = "EditFlow.ApplyEdits.HostRead"
			public static let hostWrite: StaticString = "EditFlow.ApplyEdits.HostWrite"
			public static let engineApply: StaticString = "EditFlow.ApplyEdits.EngineApply"
			public static let diffGeneration: StaticString = "EditFlow.ApplyEdits.DiffGeneration"
			public static let patchApply: StaticString = "EditFlow.ApplyEdits.PatchApply"
			public static let toolCardDiff: StaticString = "EditFlow.ApplyEdits.ToolCardDiff"
			public static let format: StaticString = "EditFlow.ApplyEdits.Format"
			public static let formatDecode: StaticString = "EditFlow.ApplyEdits.FormatDecode"
			public static let formatMarkdown: StaticString = "EditFlow.ApplyEdits.FormatMarkdown"
			public static let formatResource: StaticString = "EditFlow.ApplyEdits.FormatResource"
			public static let approvalWait: StaticString = "EditFlow.ApplyEdits.ApprovalWait"
			public static let flushDeltas: StaticString = "EditFlow.ApplyEdits.FlushDeltas"
		}

		public enum Search {
			public static let entrypoint: StaticString = "EditFlow.Search.Entrypoint"
			public static let scopeFiltering: StaticString = "EditFlow.Search.ScopeFiltering"
			public static let actorSearchCall: StaticString = "EditFlow.Search.ActorSearchCall"
			public static let actorSearchUnified: StaticString = "EditFlow.Search.ActorSearchUnified"
			public static let contentBatch: StaticString = "EditFlow.Search.ContentBatch"
			public static let pathBatch: StaticString = "EditFlow.Search.PathBatch"
			public static let fileContentFetch: StaticString = "EditFlow.Search.FileContentFetch"
			public static let lineIndexCacheKey: StaticString = "EditFlow.Search.LineIndexCacheKey"
			public static let lineIndexLookup: StaticString = "EditFlow.Search.LineIndexLookup"
			public static let lineIndexBuild: StaticString = "EditFlow.Search.LineIndexBuild"
			public static let countOnlyFastPath: StaticString = "EditFlow.Search.CountOnlyFastPath"
			public static let regexFullBufferScan: StaticString = "EditFlow.Search.RegexFullBufferScan"
			public static let regexLineByLineScan: StaticString = "EditFlow.Search.RegexLineByLineScan"
			public static let literalScan: StaticString = "EditFlow.Search.LiteralScan"
			public static let materializeMatches: StaticString = "EditFlow.Search.MaterializeMatches"
		}

		public enum Transcript {
			public static let scheduleRefresh: StaticString = "EditFlow.Transcript.ScheduleRefresh"
			public static let refreshTotal: StaticString = "EditFlow.Transcript.RefreshTotal"
			public static let importTranscript: StaticString = "EditFlow.Transcript.ImportTranscript"
			public static let incrementalImport: StaticString = "EditFlow.Transcript.IncrementalImport"
			public static let payloadMap: StaticString = "EditFlow.Transcript.PayloadMap"
			public static let sanitize: StaticString = "EditFlow.Transcript.Sanitize"
			public static let projectionBuild: StaticString = "EditFlow.Transcript.ProjectionBuild"
			public static let publish: StaticString = "EditFlow.Transcript.Publish"
			public static let toolProcessing: StaticString = "EditFlow.Transcript.ToolProcessing"
		}

		public enum Parser {
			public static let chatContentParse: StaticString = "EditFlow.Parser.ChatContentParse"
			public static let chatDelegateEditParse: StaticString = "EditFlow.Parser.ChatDelegateEditParse"
			public static let diffParseChanges: StaticString = "EditFlow.Parser.DiffParseChanges"
			public static let diffRegexCacheLookup: StaticString = "EditFlow.Parser.DiffRegexCacheLookup"
		}

		public enum DelegateSandbox {
			public static let readFile: StaticString = "EditFlow.DelegateSandbox.ReadFile"
			public static let fileSearch: StaticString = "EditFlow.DelegateSandbox.FileSearch"
			public static let applyEdits: StaticString = "EditFlow.DelegateSandbox.ApplyEdits"
			public static let regexCompile: StaticString = "EditFlow.DelegateSandbox.RegexCompile"
		}

		public enum Delegate {
			public static let runForFile: StaticString = "EditFlow.Delegate.RunForFile"
			public static let taskSpawn: StaticString = "EditFlow.Delegate.TaskSpawn"
			public static let taskDuplicateSkip: StaticString = "EditFlow.Delegate.TaskDuplicateSkip"
			public static let watchdogArm: StaticString = "EditFlow.Delegate.WatchdogArm"
			public static let watchdogSkip: StaticString = "EditFlow.Delegate.WatchdogSkip"
			public static let watchdogCancel: StaticString = "EditFlow.Delegate.WatchdogCancel"
			public static let watchdogComplete: StaticString = "EditFlow.Delegate.WatchdogComplete"
			public static let observerRegister: StaticString = "EditFlow.Delegate.ObserverRegister"
			public static let observerUnregister: StaticString = "EditFlow.Delegate.ObserverUnregister"
		}

		public enum UnifiedDiff {
			public static let parseForRender: StaticString = "EditFlow.UnifiedDiff.ParseForRender"
			public static let attributedBuild: StaticString = "EditFlow.UnifiedDiff.AttributedBuild"
		}

		public enum Git {
			public static let hunkParsing: StaticString = "EditFlow.Git.HunkParsing"
		}
	}

	#if DEBUG || EDIT_FLOW_PERF
	private static let signposter = OSSignposter(subsystem: "com.repoprompt.edit-flow", category: "perf")
	private static let logger = Logger(subsystem: "com.repoprompt.edit-flow", category: "perf")
	private static let environmentEnabled: Bool = {
		guard let raw = ProcessInfo.processInfo.environment["REPOPROMPT_EDIT_FLOW_PERF"] else {
			return false
		}
		let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		return ["1", "true", "yes", "y", "on"].contains(value)
	}()

	public static var isEnabled: Bool {
		environmentEnabled || UserDefaults.standard.bool(forKey: "editFlowPerfEnabled")
	}

	@discardableResult
	public static func begin(_ name: StaticString) -> IntervalState? {
		guard isEnabled else { return nil }
		return signposter.beginInterval(name)
	}

	@discardableResult
	public static func begin(_ name: StaticString, _ dimensions: @autoclosure () -> Dimensions) -> IntervalState? {
		guard isEnabled else { return nil }
		logDimensions(dimensions())
		return signposter.beginInterval(name)
	}

	public static func end(_ name: StaticString, _ state: IntervalState?) {
		guard let state else { return }
		signposter.endInterval(name, state)
	}

	public static func end(_ name: StaticString, _ state: IntervalState?, _ dimensions: @autoclosure () -> Dimensions) {
		guard let state else { return }
		if isEnabled {
			logDimensions(dimensions())
		}
		signposter.endInterval(name, state)
	}

	public static func event(_ name: StaticString) {
		guard isEnabled else { return }
		signposter.emitEvent(name)
	}

	public static func event(_ name: StaticString, _ dimensions: @autoclosure () -> Dimensions) {
		guard isEnabled else { return }
		logDimensions(dimensions())
		signposter.emitEvent(name)
	}

	public static func measure<T>(
		_ name: StaticString,
		operation: () throws -> T
	) rethrows -> T {
		let state = begin(name)
		defer { end(name, state) }
		return try operation()
	}

	public static func measure<T>(
		_ name: StaticString,
		_ dimensions: @autoclosure () -> Dimensions,
		operation: () throws -> T
	) rethrows -> T {
		let state = begin(name, dimensions())
		defer { end(name, state) }
		return try operation()
	}

	public static func measure<T>(
		_ name: StaticString,
		operation: () async throws -> T
	) async rethrows -> T {
		let state = begin(name)
		defer { end(name, state) }
		return try await operation()
	}

	public static func measure<T>(
		_ name: StaticString,
		_ dimensions: @autoclosure () -> Dimensions,
		operation: () async throws -> T
	) async rethrows -> T {
		let state = begin(name, dimensions())
		defer { end(name, state) }
		return try await operation()
	}

	private static func logDimensions(_ dimensions: Dimensions) {
		guard !dimensions.isEmpty else { return }
		logger.debug("dimensions \(dimensions.logDescription, privacy: .public)")
	}
	#else
	public static var isEnabled: Bool { false }

	@discardableResult
	@inline(__always)
	public static func begin(_ name: StaticString) -> IntervalState? {
		nil
	}

	@discardableResult
	@inline(__always)
	public static func begin(_ name: StaticString, _ dimensions: @autoclosure () -> Dimensions) -> IntervalState? {
		nil
	}

	@inline(__always)
	public static func end(_ name: StaticString, _ state: IntervalState?) {}

	@inline(__always)
	public static func end(_ name: StaticString, _ state: IntervalState?, _ dimensions: @autoclosure () -> Dimensions) {}

	@inline(__always)
	public static func event(_ name: StaticString) {}

	@inline(__always)
	public static func event(_ name: StaticString, _ dimensions: @autoclosure () -> Dimensions) {}

	@inline(__always)
	public static func measure<T>(
		_ name: StaticString,
		operation: () throws -> T
	) rethrows -> T {
		try operation()
	}

	@inline(__always)
	public static func measure<T>(
		_ name: StaticString,
		_ dimensions: @autoclosure () -> Dimensions,
		operation: () throws -> T
	) rethrows -> T {
		try operation()
	}

	@inline(__always)
	public static func measure<T>(
		_ name: StaticString,
		operation: () async throws -> T
	) async rethrows -> T {
		try await operation()
	}

	@inline(__always)
	public static func measure<T>(
		_ name: StaticString,
		_ dimensions: @autoclosure () -> Dimensions,
		operation: () async throws -> T
	) async rethrows -> T {
		try await operation()
	}
	#endif
}
