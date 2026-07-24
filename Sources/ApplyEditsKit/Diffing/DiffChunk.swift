import Foundation

public struct DiffChunk: Equatable {
	public var lines: [DiffLine]
	public var startLine: Int
	
	public init(lines: [DiffLine], startLine: Int) {
		self.lines = lines
		self.startLine = startLine
	}
	
	public func lineCountDifference() -> Int {
		lines.reduce(0) { count, line in
			switch line.type {
			case .addition: return count + 1
			case .removal: return count - 1
			case .context: return count
			}
		}
	}
	
	/// Number of lines that appear in the old version (context + removals)
	public var oldLineCount: Int {
		lines.filter { $0.type == .context || $0.type == .removal }.count
	}
	
	/// Number of lines that appear in the new version (context + additions)
	public var newLineCount: Int {
		lines.filter { $0.type == .context || $0.type == .addition }.count
	}
	
	public func getChunkWithEncodedIndendation() -> DiffChunk {
		let encodedLines = self.lines.map { line in
			let prefix = line.prefix
			return DiffLine(content: prefix + String.encodeIndentation(line.content))
		}
		return DiffChunk(lines: encodedLines, startLine: self.startLine)
	}
	
	public func getChunkWithDecodedIndentation() -> DiffChunk {
		let decodedLines = self.lines.map { line in
			let prefix = line.prefix
			return DiffLine(content: prefix + String.decodeIndentation(line.content))
		}
		return DiffChunk(lines: decodedLines, startLine: self.startLine)
	}
	
	private func scoreMatch(in content: [String], startingAt line: Int) -> Int {
		var score = 0
		let windowSize = min(lines.count, 3)
		
		for i in 0..<windowSize {
			if line + i < content.count && lines[i].type == .context {
				let contextLine = lines[i].content
				let contentLine = content[line + i]
				if contextLine.isSimilar(to: contentLine, threshold: 0.8) {
					score += 1
				}
			}
		}
		
		return score
	}
	
	// Implement Equatable
	public static func == (lhs: DiffChunk, rhs: DiffChunk) -> Bool {
		return lhs.lines == rhs.lines
	}
}

import Foundation

public struct DiffLine: Equatable {
	public enum LineType: Equatable {
		case addition
		case removal
		case context
	}
	
	public let type: LineType
	public var content: String
	public let rawContent: String
	
	public init(content: String) {
		self.rawContent = content
		switch content.prefix(1) {
		case "+":
			self.type = .addition
			self.content = String(content.dropFirst())
		case "-":
			self.type = .removal
			self.content = String(content.dropFirst())
		default:
			self.type = .context
			self.content = String(content.dropFirst())
		}
	}
	
	public var prefix: String {
		switch type {
		case .addition: return "+"
		case .removal: return "-"
		case .context: return " "
		}
	}
	
	// Implement Equatable with fuzzy comparison
	public static func == (lhs: DiffLine, rhs: DiffLine) -> Bool {
		return lhs.type == rhs.type &&
		lhs.content.isSimilar(to: rhs.content, threshold: 0.9) &&
		lhs.rawContent.isSimilar(to: rhs.rawContent, threshold: 0.9)
	}
}
