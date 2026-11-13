import Foundation

public struct ApplyEditsEngine {
	public let diffEngine: DiffChunkGenerator
	public let patchApplier: DiffChunkApplier
	public let unifiedDiffRenderer: UnifiedDiffRendering

	public init(
		diffEngine: DiffChunkGenerator,
		patchApplier: DiffChunkApplier,
		unifiedDiffRenderer: UnifiedDiffRendering
	) {
		self.diffEngine = diffEngine
		self.patchApplier = patchApplier
		self.unifiedDiffRenderer = unifiedDiffRenderer
	}

	public static var `default`: ApplyEditsEngine {
		ApplyEditsEngine(
			diffEngine: DefaultDiffChunkGenerator(),
			patchApplier: DefaultDiffChunkApplier(),
			unifiedDiffRenderer: DefaultUnifiedDiffRenderer()
		)
	}

	public func apply(
		request: ApplyEditsRequest,
		to originalText: String,
		options: ApplyEditsExecutionOptions = .default
	) async throws -> ApplyEditsResult {
		let state = EditFlowPerf.begin(
			EditFlowPerf.Stage.ApplyEdits.engineApply,
			EditFlowPerf.Dimensions(
				fileBytes: originalText.utf8.count,
				editCount: request.editCount,
				includesToolCardDiff: options.includeToolCardUnifiedDiff
			)
		)
		defer { EditFlowPerf.end(EditFlowPerf.Stage.ApplyEdits.engineApply, state) }

		switch request.mode {
		case .rewrite(let newText, _):
			let single = try await applySingle(
				filePath: request.path,
				originalText: originalText,
				search: nil,
				replace: newText,
				replaceAll: false,
				treatAsRewrite: true
			)
			return buildResult(
				originalText: originalText,
				updatedText: single.updatedText,
				diffChunks: single.diffChunks,
				note: single.note,
				editsRequested: 1,
				editsApplied: 1,
				status: .success,
				outcomes: nil,
				path: request.path,
				verbose: request.verbose,
				options: options
			)

		case .single(let search, let replace, let replaceAll):
			let single = try await applySingle(
				filePath: request.path,
				originalText: originalText,
				search: search,
				replace: replace,
				replaceAll: replaceAll,
				treatAsRewrite: false
			)
			return buildResult(
				originalText: originalText,
				updatedText: single.updatedText,
				diffChunks: single.diffChunks,
				note: single.note,
				editsRequested: 1,
				editsApplied: 1,
				status: .success,
				outcomes: nil,
				path: request.path,
				verbose: request.verbose,
				options: options
			)

		case .batch(let edits):
			return try await applyBatch(
				edits: edits,
				originalText: originalText,
				path: request.path,
				verbose: request.verbose,
				options: options
			)
		}
	}

	private func applySingle(
		filePath: String,
		originalText: String,
		search: String?,
		replace: String,
		replaceAll: Bool,
		treatAsRewrite: Bool
	) async throws -> (updatedText: String, diffChunks: [DiffChunk], note: String?) {
		var effectiveSearch = search
		var effectiveReplace = replace
		var usedEscapeFallback = false
		if let search, !treatAsRewrite {
			let fallback = ApplyEditsEscapeFallback()
			let resolved = fallback.resolveSingle(search: search, replace: replace, in: originalText)
			effectiveSearch = resolved.search
			effectiveReplace = resolved.replace
			usedEscapeFallback = resolved.usedFallback
		}

		let generation = try await EditFlowPerf.measure(
			EditFlowPerf.Stage.ApplyEdits.diffGeneration,
			EditFlowPerf.Dimensions(fileBytes: originalText.utf8.count)
		) {
			try await diffEngine.makeEdit(
				filePath: filePath,
				originalText: originalText,
				search: effectiveSearch,
				replace: effectiveReplace,
				replaceAll: replaceAll,
				treatAsRewrite: treatAsRewrite
			)
		}
		let note = Self.combinedNote(usedEscapeFallback ? Self.escapeFallbackNote : nil, generation.note)
		if let updatedText = generation.updatedText {
			return (updatedText: updatedText, diffChunks: generation.chunks, note: note)
		}
		let updatedText = try EditFlowPerf.measure(
			EditFlowPerf.Stage.ApplyEdits.patchApply,
			EditFlowPerf.Dimensions(chunkCount: generation.chunks.count)
		) {
			try patchApplier.apply(
				chunks: generation.chunks,
				to: originalText,
				fileAction: generation.fileAction
			)
		}
		return (updatedText: updatedText, diffChunks: generation.chunks, note: note)
	}

	private func applyBatch(
		edits: [ApplyEditsOperation],
		originalText: String,
		path: String,
		verbose: Bool,
		options: ApplyEditsExecutionOptions
	) async throws -> ApplyEditsResult {
		guard !edits.isEmpty else {
			throw ApplyEditsError.invalidParams("edits array cannot be empty")
		}

		// The escape fallback is resolved per edit, against the text that edit
		// is applied to (edits apply in sequence).
		if let literalResult = tryLiteralBatch(
			edits: edits,
			originalText: originalText,
			path: path,
			verbose: verbose,
			options: options
		) {
			return literalResult
		}

		return applyBatchSequentially(
			edits: edits,
			originalText: originalText,
			path: path,
			verbose: verbose,
			options: options
		)
	}

	/// Applies the edits one after another, each to the result of the
	/// previous ones (the semantics of `tryLiteralBatch`). An edit whose
	/// search no longer matches — including text an earlier edit consumed —
	/// fails on its own and the rest still apply. Repeated identical searches
	/// take successive occurrences instead of failing as ambiguous.
	private func applyBatchSequentially(
		edits: [ApplyEditsOperation],
		originalText: String,
		path: String,
		verbose: Bool,
		options: ApplyEditsExecutionOptions
	) -> ApplyEditsResult {
		var searchCounts: [String: Int] = [:]
		for edit in edits {
			searchCounts[edit.search, default: 0] += 1
		}

		var text = originalText
		var outcomes: [EditOutcome] = []
		outcomes.reserveCapacity(edits.count)
		var cursors: [String: Int] = [:]
		var applied = 0
		var usedEscapeFallback = false
		var editNotes: [String] = []
		let fallback = ApplyEditsEscapeFallback()

		EditFlowPerf.measure(
			EditFlowPerf.Stage.ApplyEdits.patchApply,
			EditFlowPerf.Dimensions(fileBytes: originalText.utf8.count, editCount: edits.count)
		) {
			for (index, edit) in edits.enumerated() {
				let takesNextOccurrence = !edit.replaceAll && (searchCounts[edit.search] ?? 0) > 1
				let resolved = fallback.resolveSingle(search: edit.search, replace: edit.replace, in: text)
				do {
					let outcome = try TextEditApplier.apply(
						search: resolved.search,
						replace: resolved.replace,
						replaceAll: edit.replaceAll,
						to: text,
						path: path,
						firstMatchAtOrAfter: takesNextOccurrence ? (cursors[edit.search] ?? 0) : nil
					)
					for (key, offset) in cursors {
						cursors[key] = TextEditApplier.shift(offset, by: outcome.regions)
					}
					if takesNextOccurrence, let region = outcome.regions.first {
						cursors[edit.search] = region.start + region.newLength
					}
					text = outcome.text
					applied += 1
					usedEscapeFallback = usedEscapeFallback || resolved.usedFallback
					if let note = outcome.note {
						editNotes.append("Edit \(index + 1): \(note)")
					}
					outcomes.append(EditOutcome(index: index, status: "success", error: nil))
				} catch {
					outcomes.append(EditOutcome(index: index, status: "failed", error: Self.message(for: error)))
				}
			}
		}

		if applied == 0 {
			return ApplyEditsResult(
				updatedText: originalText,
				diffChunks: [],
				unifiedDiff: nil,
				toolCardUnifiedDiff: nil,
				stats: nil,
				note: nil,
				fileCreated: false,
				fileOverwritten: false,
				editsRequested: edits.count,
				editsApplied: 0,
				status: .failed,
				outcomes: outcomes
			)
		}

		let chunks = EditFlowPerf.measure(
			EditFlowPerf.Stage.ApplyEdits.diffGeneration,
			EditFlowPerf.Dimensions(fileBytes: originalText.utf8.count, editCount: edits.count)
		) {
			ApplyEditsDisplayDiff.chunks(original: originalText, updated: text)
		}
		let status: ApplyEditsStatus = applied == edits.count ? .success : .partial
		return buildResult(
			originalText: originalText,
			updatedText: text,
			diffChunks: chunks,
			note: Self.combinedNote(
				usedEscapeFallback ? Self.escapeFallbackNote : nil,
				editNotes.isEmpty ? nil : editNotes.joined(separator: " ")
			),
			editsRequested: edits.count,
			editsApplied: applied,
			status: status,
			outcomes: outcomes,
			path: path,
			verbose: verbose,
			options: options
		)
	}

	static let escapeFallbackNote =
		"The search matched only after decoding backslash escapes (such as \\n); the replacement's escapes of the same kinds were decoded too."

	private static func combinedNote(_ first: String?, _ second: String?) -> String? {
		switch (first, second) {
		case let (first?, second?): return first + " " + second
		case let (first?, nil): return first
		case let (nil, second?): return second
		case (nil, nil): return nil
		}
	}

	private static func message(for error: Error) -> String {
		switch error {
		case ApplyEditsError.invalidParams(let message), ApplyEditsError.internalError(let message):
			return message
		default:
			return error.localizedDescription
		}
	}

	private func tryLiteralBatch(
		edits: [ApplyEditsOperation],
		originalText: String,
		path: String,
		verbose: Bool,
		options: ApplyEditsExecutionOptions
	) -> ApplyEditsResult? {
		var newText = originalText
		var outcomes: [EditOutcome] = []
		var appliedCount = 0
		let fallback = ApplyEditsEscapeFallback()

		for (idx, rawEdit) in edits.enumerated() {
			let resolved = fallback.resolveSingle(search: rawEdit.search, replace: rawEdit.replace, in: newText)
			// A literal fast path only: an edit that needs escape decoding is
			// left to the sequential path, which reports it.
			guard !resolved.usedFallback else { return nil }
			let edit = rawEdit
			let matches = newText.ranges(of: edit.search)
			if edit.replaceAll {
				guard !matches.isEmpty else { return nil }
				newText = newText.replacingOccurrences(of: edit.search, with: edit.replace)
				outcomes.append(EditOutcome(index: idx, status: "success", error: nil))
				appliedCount += 1
			} else {
				guard matches.count == 1 else { return nil }
				newText.replaceSubrange(matches[0], with: edit.replace)
				outcomes.append(EditOutcome(index: idx, status: "success", error: nil))
				appliedCount += 1
			}
		}

		let chunks = EditFlowPerf.measure(
			EditFlowPerf.Stage.ApplyEdits.diffGeneration,
			EditFlowPerf.Dimensions(fileBytes: originalText.utf8.count, editCount: edits.count)
		) {
			ApplyEditsDisplayDiff.chunks(original: originalText, updated: newText)
		}

		return buildResult(
			originalText: originalText,
			updatedText: newText,
			diffChunks: chunks,
			note: "Applied via exact literal replacement",
			editsRequested: edits.count,
			editsApplied: appliedCount,
			status: .success,
			outcomes: verbose ? outcomes : nil,
			path: path,
			verbose: verbose,
			options: options
		)
	}

	private func buildResult(
		originalText: String,
		updatedText: String,
		diffChunks: [DiffChunk],
		note: String?,
		editsRequested: Int,
		editsApplied: Int,
		status: ApplyEditsStatus,
		outcomes: [EditOutcome]?,
		path: String,
		verbose: Bool,
		options: ApplyEditsExecutionOptions
	) -> ApplyEditsResult {
		// Chunks are derived from the exact text written, so a whitespace-
		// only change is a real change and is shown, not filtered out.
		let filteredChunks = diffChunks
		let note = Self.combinedNote(
			note,
			ApplyEditsDisplayDiff.onlyLineEndingsDiffer(original: originalText, updated: updatedText)
				? "Only line endings changed; the diff shows the lines whose ending changed."
				: nil
		)
		let stats: ApplyEditsStats?
		if filteredChunks.isEmpty {
			stats = nil
		} else {
			let raw = UnifiedDiffGenerator.stats(from: filteredChunks)
			stats = ApplyEditsStats(linesChanged: raw.linesChanged, chunks: raw.chunks)
		}

		let unifiedDiff: String?
		if verbose {
			unifiedDiff = unifiedDiffRenderer.render(filePath: path, chunks: filteredChunks)
		} else {
			unifiedDiff = nil
		}

		let toolCardUnifiedDiff: String?
		if options.includeToolCardUnifiedDiff {
			toolCardUnifiedDiff = EditFlowPerf.measure(
				EditFlowPerf.Stage.ApplyEdits.toolCardDiff,
				EditFlowPerf.Dimensions(
					fileBytes: originalText.utf8.count,
					chunkCount: filteredChunks.count
				)
			) {
				buildToolCardUnifiedDiff(
					path: path,
					originalText: originalText,
					updatedText: updatedText,
					fallbackChunks: filteredChunks
				)
			}
		} else {
			toolCardUnifiedDiff = nil
		}

		return ApplyEditsResult(
			updatedText: updatedText,
			diffChunks: filteredChunks,
			unifiedDiff: unifiedDiff,
			toolCardUnifiedDiff: toolCardUnifiedDiff,
			stats: stats,
			note: note,
			fileCreated: false,
			fileOverwritten: false,
			editsRequested: editsRequested,
			editsApplied: editsApplied,
			status: status,
			outcomes: outcomes
		)
	}

	private func buildToolCardUnifiedDiff(
		path: String,
		originalText: String,
		updatedText: String,
		fallbackChunks: [DiffChunk]
	) -> String? {
		guard !fallbackChunks.isEmpty else { return nil }

		let contextLines = 2
		let contextualChunks = ApplyEditsDisplayDiff.toolCardChunks(
			original: originalText,
			updated: updatedText,
			context: contextLines
		)

		if !contextualChunks.isEmpty {
			return UnifiedDiffGenerator.build(
				filePath: path,
				chunks: contextualChunks,
				context: contextLines
			)
		}

		let decodedFallbackChunks = fallbackChunks.map { $0.getChunkWithDecodedIndentation() }
		return UnifiedDiffGenerator.buildFromEditChunks(
			filePath: path,
			chunks: decodedFallbackChunks,
			startLineBase: .oneBased
		)
	}
}

/// The engine's default edit generator. It computes the updated text with
/// `TextEditApplier` (literal match, else a verified whitespace-lenient line
/// match, else "not found"; `rewrite` takes the new text verbatim) and
/// derives the chunks from that text for display.
public struct DefaultDiffChunkGenerator: DiffChunkGenerator {
	public init() {}

	public func makeDiffChunks(
		filePath: String,
		originalText: String,
		search: String?,
		replace: String,
		replaceAll: Bool,
		treatAsRewrite: Bool
	) async throws -> (chunks: [DiffChunk], fileAction: FileAction) {
		let generation = try await makeEdit(
			filePath: filePath,
			originalText: originalText,
			search: search,
			replace: replace,
			replaceAll: replaceAll,
			treatAsRewrite: treatAsRewrite
		)
		return (generation.chunks, generation.fileAction)
	}

	public func makeEdit(
		filePath: String,
		originalText: String,
		search: String?,
		replace: String,
		replaceAll: Bool,
		treatAsRewrite: Bool
	) async throws -> DiffChunkGeneration {
		let searchRaw = treatAsRewrite ? "" : (search ?? "")
		let outcome = try TextEditApplier.apply(
			search: searchRaw,
			replace: replace,
			replaceAll: replaceAll,
			to: originalText,
			path: filePath
		)
		let chunks = ApplyEditsDisplayDiff.chunks(original: originalText, updated: outcome.text)
		let action: FileAction = searchRaw.isEmpty ? .rewrite : .modify
		return DiffChunkGeneration(chunks: chunks, fileAction: action, updatedText: outcome.text, note: outcome.note)
	}
}

/// Applies indentation-encoded chunks (start lines in original-file
/// coordinates, as `DiffChunkGenerator`s produce them) to the original text.
/// Untouched lines keep their own bytes and line endings; added lines take
/// the file's dominant ending. Every context and removed line must match the
/// file line it lands on (ignoring whitespace) and chunks must not overlap,
/// otherwise the application fails instead of rewriting the wrong lines.
/// No chunks means no change.
public struct DefaultDiffChunkApplier: DiffChunkApplier {
	public init() {}

	public func apply(chunks: [DiffChunk], to originalText: String, fileAction: FileAction) throws -> String {
		guard !chunks.isEmpty else { return originalText }

		let lines = String.splitContentPreservingAllLineEndings(originalText)
		let lineEnding = String.splitContentPreservingLineEndings(originalText).1
		let decodedChunks = chunks
			.map { $0.getChunkWithDecodedIndentation() }
			.sorted { $0.startLine < $1.startLine }

		var output: [(line: String, ending: String)] = []
		output.reserveCapacity(lines.count)
		var cursor = 0
		for chunk in decodedChunks {
			guard chunk.startLine >= cursor, chunk.startLine <= lines.count else {
				throw ApplyEditsError.internalError(
					"diff application failed: a change at line \(chunk.startLine + 1) overlaps another change or lies outside the file"
				)
			}
			output.append(contentsOf: lines[cursor..<chunk.startLine])
			cursor = chunk.startLine
			for line in chunk.lines {
				switch line.type {
				case .context, .removal:
					guard cursor < lines.count,
						  TextEditApplier.lineMatchKey(lines[cursor].line) == TextEditApplier.lineMatchKey(line.content)
					else {
						throw ApplyEditsError.internalError(
							"diff application failed: line \(cursor + 1) of the file does not match the change"
						)
					}
					if line.type == .context {
						output.append(lines[cursor])
					}
					cursor += 1
				case .addition:
					output.append((line.content, lineEnding))
				}
			}
		}
		output.append(contentsOf: lines[cursor...])

		let hadFinalEnding = !(lines.last?.ending.isEmpty ?? true)
		var result = ""
		result.reserveCapacity(originalText.utf8.count)
		for (index, entry) in output.enumerated() {
			result += entry.line
			if index < output.count - 1 {
				result += entry.ending.isEmpty ? lineEnding : entry.ending
			} else if hadFinalEnding {
				result += entry.ending.isEmpty ? lineEnding : entry.ending
			}
		}
		return result
	}
}

public struct DefaultUnifiedDiffRenderer: UnifiedDiffRendering {
	public func render(filePath: String, chunks: [DiffChunk]) -> String {
		let decodedChunks = chunks.map { $0.getChunkWithDecodedIndentation() }
		return UnifiedDiffGenerator.buildFromEditChunks(
			filePath: filePath,
			chunks: decodedChunks,
			startLineBase: .zeroBased
		)
	}
}
