import Foundation

/// `Sendable` because every stored property is a value type (`UUID`,
/// `String`, `Int`, `DiffChunk`). The conformance is additive and is what
/// lets the `dummy` static constant below be a concurrency-safe global
/// under the Swift 6 language mode.
public struct FileChange: Identifiable, Equatable, Codable, Sendable {
	public let id: UUID
	public let description: String
	public var startLine: Int
	public var diffChunk: DiffChunk
	public static let dummy = FileChange(id: UUID(), startLine: 0, description: "No change", diffChunk: DiffChunk(lines: [], startLine: 0))
	
	public enum CodingKeys: String, CodingKey {
		case startLine = "start_line"
		case description
		case chunk
	}
	
	public init(id: UUID = UUID(), startLine: Int, description: String, diffChunk: DiffChunk) {
		self.id = id
		self.startLine = startLine
		self.description = description
		self.diffChunk = diffChunk
	}
	
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.id = UUID()
		self.startLine = try container.decode(Int.self, forKey: .startLine)
		self.description = try container.decode(String.self, forKey: .description)
		let chunkLines = try container.decode([String].self, forKey: .chunk)
		self.diffChunk = DiffChunk(lines: chunkLines.map { DiffLine(content: $0) }, startLine: startLine)
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(startLine, forKey: .startLine)
		try container.encode(description, forKey: .description)
		try container.encode(diffChunk.lines.map { $0.rawContent }, forKey: .chunk)
	}
	
	// Implement Equatable
	public static func == (lhs: FileChange, rhs: FileChange) -> Bool {
		return lhs.id == rhs.id &&
		lhs.description == rhs.description &&
		lhs.startLine == rhs.startLine &&
		lhs.diffChunk == rhs.diffChunk
	}
	
	// New function to print all lines in the file change
	public func printAllLines() {
		print("File Change ID: \(id)")
		print("Description: \(description)")
		print("Start Line: \(startLine)")
		print("Diff Chunk:")
		for (index, line) in diffChunk.lines.enumerated() {
			print("  Line \(index + 1): \(line.rawContent)")
		}
		print("") // Empty line for better readability
	}
	
	/// A stable, human-readable identity built from the change's content.
	///
	/// *Important*: use the immutable `diffChunk.startLine` rather than the
	/// mutable `startLine`.
	/// When changes are applied (or reverted) `startLine` is adjusted,
	/// causing any key computed from it *afterwards* to drift.
	/// Persisting that drifting key made most changes fail to match during a
	/// restore – we’d only hit whichever change happened not to shift.
	public var contentKey: String {
		[
			description.trimmingCharacters(in: .whitespacesAndNewlines),
			String(diffChunk.startLine),                     // ← fixed
			diffChunk.lines.map(\.rawContent).joined(separator: "\n")
		]
			.joined(separator: "|")
	}
}
