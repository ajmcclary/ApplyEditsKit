import CryptoKit
import Foundation

public struct ApplyEditsService {
	public let engine: ApplyEditsEngine
	public let host: FileEditHost

	public init(engine: ApplyEditsEngine, host: FileEditHost) {
		self.engine = engine
		self.host = host
	}

	/// Computes the edit and writes it, refusing if the file changed while
	/// the edit was being computed. Equivalent to `commit(prepare(request))`.
	public func run(
		_ request: ApplyEditsRequest,
		options: ApplyEditsExecutionOptions = .default
	) async throws -> ApplyEditsResult {
		let state = EditFlowPerf.begin(
			EditFlowPerf.Stage.ApplyEdits.serviceRun,
			EditFlowPerf.Dimensions(editCount: request.editCount, includesToolCardDiff: options.includeToolCardUnifiedDiff)
		)
		defer { EditFlowPerf.end(EditFlowPerf.Stage.ApplyEdits.serviceRun, state) }

		let prepared = try await prepare(request, options: options)
		return try await commit(prepared)
	}

	/// Computes the edit without writing it. The returned value records the
	/// identity of the exact text the edit was computed from (or that the
	/// file did not exist), so a later `commit` can refuse to overwrite a
	/// change made in between — for example while a user reviews the edit.
	public func prepare(
		_ request: ApplyEditsRequest,
		options: ApplyEditsExecutionOptions = .default
	) async throws -> ApplyEditsPreparedEdit {
		let previewed = try await preview(request, options: options)
		return ApplyEditsPreparedEdit(
			path: request.path,
			base: previewed.originalText.map { ApplyEditsBaseIdentity(text: $0) },
			result: previewed.result
		)
	}

	/// Writes a prepared edit if the file is still exactly what it was
	/// computed from: re-reads through the host and throws
	/// `ApplyEditsFileChangedError` — writing nothing — if the content
	/// differs, the file was deleted, or (for a create) a file appeared.
	/// An edit that applied nothing writes nothing.
	///
	/// The host port has no atomic compare-and-swap, so a change landing
	/// between this re-read and the write is still possible; the window is
	/// the duration of one read.
	public func commit(_ prepared: ApplyEditsPreparedEdit) async throws -> ApplyEditsResult {
		let result = prepared.result
		let created = prepared.base == nil
		guard result.editsApplied > 0 else {
			return result.withFileMetadata(created: created, overwritten: false)
		}

		let existsNow = await host.fileExists(path: prepared.path)
		if let base = prepared.base {
			guard existsNow else {
				throw ApplyEditsFileChangedError(path: prepared.path, reason: .fileDeleted)
			}
			let currentText = try await host.readText(path: prepared.path)
			guard ApplyEditsBaseIdentity(text: currentText) == base else {
				throw ApplyEditsFileChangedError(path: prepared.path, reason: .contentChanged)
			}
		} else if existsNow {
			throw ApplyEditsFileChangedError(path: prepared.path, reason: .fileCreated)
		}

		try await EditFlowPerf.measure(
			EditFlowPerf.Stage.ApplyEdits.hostWrite,
			EditFlowPerf.Dimensions(fileBytes: result.updatedText.utf8.count, appliedCount: result.editsApplied)
		) {
			try await host.writeText(
				path: prepared.path,
				content: result.updatedText,
				overwrite: !created
			)
		}
		return result.withFileMetadata(created: created, overwritten: false)
	}

	public func preview(
		_ request: ApplyEditsRequest,
		options: ApplyEditsExecutionOptions = .default
	) async throws -> (exists: Bool, originalText: String?, result: ApplyEditsResult) {
		let state = EditFlowPerf.begin(
			EditFlowPerf.Stage.ApplyEdits.servicePreview,
			EditFlowPerf.Dimensions(editCount: request.editCount, includesToolCardDiff: options.includeToolCardUnifiedDiff)
		)
		defer { EditFlowPerf.end(EditFlowPerf.Stage.ApplyEdits.servicePreview, state) }

		let exists = await host.fileExists(path: request.path)

		if !exists {
			switch request.mode {
			case .rewrite(let newText, let onMissing):
				guard onMissing == .create else {
					throw ApplyEditsError.invalidParams(
						"File '\(request.path)' does not exist. Use `on_missing=\"create\"` with `rewrite`, or create the file first via `file_actions` action=\"create\"."
					)
				}
				let result = buildCreateResult(text: newText, path: request.path, verbose: request.verbose, options: options)
				return (exists: false, originalText: nil, result: result)
			default:
				throw ApplyEditsError.invalidParams(
					"File '\(request.path)' does not exist. Use `on_missing=\"create\"` with `rewrite`, or create the file first via `file_actions` action=\"create\"."
				)
			}
		}

		let originalText = try await EditFlowPerf.measure(EditFlowPerf.Stage.ApplyEdits.hostRead) {
			try await host.readText(path: request.path)
		}
		EditFlowPerf.event(
			EditFlowPerf.Stage.ApplyEdits.hostRead,
			EditFlowPerf.Dimensions(fileBytes: originalText.utf8.count)
		)
		let result = try await engine.apply(request: request, to: originalText, options: options)
		return (exists: true, originalText: originalText, result: result)
	}

	private func buildCreateResult(
		text: String,
		path: String,
		verbose: Bool,
		options: ApplyEditsExecutionOptions
	) -> ApplyEditsResult {
		let newLines = String.splitContentPreservingLineEndings(text).0
		let diffChunks = UnifiedDiffGenerator.diffChunks(oldLines: [], newLines: newLines)
		let stats: ApplyEditsStats? = diffChunks.isEmpty
			? nil
			: {
				let raw = UnifiedDiffGenerator.stats(from: diffChunks)
				return ApplyEditsStats(linesChanged: raw.linesChanged, chunks: raw.chunks)
			}()

		let unifiedDiff: String?
		if verbose {
			let decodedChunks = diffChunks.map { $0.getChunkWithDecodedIndentation() }
			unifiedDiff = UnifiedDiffGenerator.buildFromEditChunks(
				filePath: path,
				chunks: decodedChunks,
				startLineBase: .oneBased
			)
		} else {
			unifiedDiff = nil
		}

		let toolCardUnifiedDiff: String?
		if options.includeToolCardUnifiedDiff {
			toolCardUnifiedDiff = EditFlowPerf.measure(
				EditFlowPerf.Stage.ApplyEdits.toolCardDiff,
				EditFlowPerf.Dimensions(lineCount: newLines.count)
			) {
				UnifiedDiffGenerator.build(
					filePath: path,
					chunks: UnifiedDiffGenerator.diffChunks(oldLines: [], newLines: newLines, context: 2),
					context: 2
				)
			}
		} else {
			toolCardUnifiedDiff = nil
		}

		return ApplyEditsResult(
			updatedText: text,
			diffChunks: diffChunks,
			unifiedDiff: unifiedDiff,
			toolCardUnifiedDiff: toolCardUnifiedDiff,
			stats: stats,
			note: nil,
			fileCreated: false,
			fileOverwritten: false,
			editsRequested: 1,
			editsApplied: 1,
			status: .success,
			outcomes: nil
		)
	}
}

/// Identity of the exact text an edit was computed from: its UTF-8 length
/// and SHA-256. Two texts have the same identity only if they are byte for
/// byte the same (a re-save that only changes line endings counts as a change).
public struct ApplyEditsBaseIdentity: Hashable, Sendable {
	public let utf8Count: Int
	/// Lowercase hex SHA-256 of the UTF-8 bytes.
	public let sha256: String

	public init(text: String) {
		let bytes = Data(text.utf8)
		self.utf8Count = bytes.count
		self.sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
	}
}

/// An edit computed by `ApplyEditsService.prepare` and not yet written.
public struct ApplyEditsPreparedEdit: Sendable {
	public let path: String
	/// Identity of the text the edit was computed from; `nil` when the file
	/// did not exist and the edit creates it.
	public let base: ApplyEditsBaseIdentity?
	public let result: ApplyEditsResult

	public init(path: String, base: ApplyEditsBaseIdentity?, result: ApplyEditsResult) {
		self.path = path
		self.base = base
		self.result = result
	}
}

/// `ApplyEditsService.commit` refused to write because the file is no
/// longer what the edit was computed from. Nothing was written.
public struct ApplyEditsFileChangedError: Error, Equatable, Sendable, LocalizedError {
	public enum Reason: String, Equatable, Sendable {
		/// The file's content differs from the previewed base.
		case contentChanged
		/// The file existed at preview time and no longer does.
		case fileDeleted
		/// The edit creates the file, but a file now exists at the path.
		case fileCreated
	}

	public let path: String
	public let reason: Reason

	public init(path: String, reason: Reason) {
		self.path = path
		self.reason = reason
	}

	public var errorDescription: String? {
		switch reason {
		case .contentChanged:
			return "File '\(path)' changed since the edit was previewed; nothing was written. Read the file again and retry."
		case .fileDeleted:
			return "File '\(path)' was deleted since the edit was previewed; nothing was written."
		case .fileCreated:
			return "File '\(path)' was created by someone else since the edit was previewed; nothing was written. Read it and retry."
		}
	}
}
