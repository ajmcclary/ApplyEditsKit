import Foundation

public protocol DiffChunkGenerator {
	func makeDiffChunks(
		filePath: String,
		originalText: String,
		search: String?,
		replace: String,
		replaceAll: Bool,
		treatAsRewrite: Bool
	) async throws -> (chunks: [DiffChunk], fileAction: FileAction)

	/// Produces the display chunks for an edit and, when the generator
	/// computed it, the exact updated text. `ApplyEditsEngine` writes
	/// `updatedText` as is and only falls back to applying `chunks` through
	/// its `DiffChunkApplier` when it is `nil`. The default implementation
	/// wraps `makeDiffChunks` and returns `nil`.
	func makeEdit(
		filePath: String,
		originalText: String,
		search: String?,
		replace: String,
		replaceAll: Bool,
		treatAsRewrite: Bool
	) async throws -> DiffChunkGeneration
}

/// Result of `DiffChunkGenerator.makeEdit`.
public struct DiffChunkGeneration: Sendable {
	public let chunks: [DiffChunk]
	public let fileAction: FileAction
	/// The text the edit produces, byte for byte, or `nil` when the
	/// generator only produced chunks.
	public let updatedText: String?
	/// Something the result must tell the caller (for example occurrences a
	/// replace_all left alone); surfaced as `ApplyEditsResult.note`.
	public let note: String?

	public init(chunks: [DiffChunk], fileAction: FileAction, updatedText: String?, note: String? = nil) {
		self.chunks = chunks
		self.fileAction = fileAction
		self.updatedText = updatedText
		self.note = note
	}
}

public extension DiffChunkGenerator {
	func makeEdit(
		filePath: String,
		originalText: String,
		search: String?,
		replace: String,
		replaceAll: Bool,
		treatAsRewrite: Bool
	) async throws -> DiffChunkGeneration {
		let result = try await makeDiffChunks(
			filePath: filePath,
			originalText: originalText,
			search: search,
			replace: replace,
			replaceAll: replaceAll,
			treatAsRewrite: treatAsRewrite
		)
		return DiffChunkGeneration(chunks: result.chunks, fileAction: result.fileAction, updatedText: nil)
	}
}

public protocol DiffChunkApplier {
	func apply(chunks: [DiffChunk], to originalText: String, fileAction: FileAction) throws -> String
}

public protocol UnifiedDiffRendering {
	func render(filePath: String, chunks: [DiffChunk]) -> String
}
