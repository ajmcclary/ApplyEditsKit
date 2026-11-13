import Foundation

/// Applies one search/replace edit to a text and returns the exact text that
/// results. This is what `ApplyEditsEngine` writes; diff chunks are derived
/// from the result for display only, never the other way round.
///
/// Matching, in order:
/// 1. **Literal.** The search text occurs verbatim. Exactly one occurrence is
///    required unless `replaceAll` is set (or a batch cursor picks one).
/// 2. **Indentation-lenient.** The search lines equal a run of whole file
///    lines once leading indentation and trailing spaces/tabs are dropped;
///    everything in between, inner whitespace included, must agree exactly.
///    The search's indentation must also map onto the matched lines' by one
///    uniform transform — a shift of the base indentation, optionally with
///    a uniform change of indent unit (tabs for spaces, 2 for 4) — so a
///    search whose nesting contradicts the file never matches it. The match
///    must be unique unless `replaceAll` is set. A search whose lines start
///    with escaped `\t` sequences is retried with those escapes read as
///    indentation (not for TeX paths).
///
/// Anything else is "not found". There is no similarity-based fallback: a
/// stale or hallucinated search block must fail rather than land on the most
/// similar region. The result is a pure function of the inputs.
///
/// Bytes: a literal match splices the replacement verbatim. A lenient match
/// replaces whole lines; untouched lines keep their own bytes and endings,
/// the replacement keeps its own bytes when the search's indentation agrees
/// with the file, and otherwise only its leading whitespace is re-based by
/// the same transform. HTML entities and backslash sequences in the
/// replacement are never decoded here (the engine's escape fallback, which
/// runs before this, is separate).
struct TextEditApplier {
	struct Region: Equatable {
		/// UTF-8 offset in the input text.
		let start: Int
		let oldLength: Int
		let newLength: Int
	}

	struct Outcome {
		let text: String
		/// Replaced regions of the input text, ascending and disjoint.
		let regions: [Region]
	}

	/// - Parameter firstMatchAtOrAfter: batch cursor for repeated identical
	///   searches; when set, the first match starting at or after this UTF-8
	///   offset is used instead of requiring a unique match.
	static func apply(
		search: String,
		replace: String,
		replaceAll: Bool,
		to text: String,
		path: String,
		firstMatchAtOrAfter cursor: Int? = nil
	) throws -> Outcome {
		if search.isEmpty {
			// An empty search block means "rewrite the whole file".
			return Outcome(
				text: replace,
				regions: [Region(start: 0, oldLength: text.utf8.count, newLength: replace.utf8.count)]
			)
		}

		if let literal = try applyLiteral(search: search, replace: replace, replaceAll: replaceAll, to: text, cursor: cursor) {
			return literal
		}
		return try applyWhitespaceLenient(
			search: search,
			replace: replace,
			replaceAll: replaceAll,
			to: text,
			path: path,
			cursor: cursor
		)
	}

	/// Maps a UTF-8 offset of the input text to the output text.
	static func shift(_ offset: Int, by regions: [Region]) -> Int {
		var delta = 0
		for region in regions {
			if offset >= region.start + region.oldLength {
				delta += region.newLength - region.oldLength
			} else if offset > region.start {
				return region.start + delta + region.newLength
			} else {
				break
			}
		}
		return offset + delta
	}

	/// Comparison key of one line: the line without its leading indentation
	/// and trailing spaces/tabs. Inner whitespace is content and is kept.
	static func lineMatchKey(_ line: String) -> String {
		let isBlank: (Character) -> Bool = { $0 == " " || $0 == "\t" }
		guard let first = line.firstIndex(where: { !isBlank($0) }),
			  let last = line.lastIndex(where: { !isBlank($0) })
		else { return "" }
		return String(line[first...last])
	}

	// MARK: - Literal

	private static func applyLiteral(
		search: String,
		replace: String,
		replaceAll: Bool,
		to text: String,
		cursor: Int?
	) throws -> Outcome? {
		let matches = text.ranges(of: search)
		guard !matches.isEmpty else { return nil }

		var offsets: [(start: Int, end: Int)] = []
		offsets.reserveCapacity(matches.count)
		var lastIndex = text.startIndex
		var lastOffset = 0
		for range in matches {
			let start = lastOffset + text.utf8.distance(from: lastIndex, to: range.lowerBound)
			let end = start + text.utf8.distance(from: range.lowerBound, to: range.upperBound)
			offsets.append((start, end))
			lastIndex = range.upperBound
			lastOffset = end
		}

		let chosen: [Int]
		if replaceAll {
			chosen = Array(offsets.indices)
		} else if let cursor {
			guard let first = offsets.firstIndex(where: { $0.start >= cursor }) else { return nil }
			chosen = [first]
		} else if offsets.count > 1 {
			let lines = offsets.map { String(lineNumber(ofUTF8Offset: $0.start, in: text)) }
			throw ApplyEditsError.invalidParams(
				"Search text matches multiple locations (lines \(lines.joined(separator: ", "))). Please make the search more specific or use replace_all=true."
			)
		} else {
			chosen = [0]
		}

		let bytes = Array(text.utf8)
		let replaceBytes = Array(replace.utf8)
		var output: [UInt8] = []
		output.reserveCapacity(bytes.count + chosen.count * max(0, replaceBytes.count - search.utf8.count))
		var regions: [Region] = []
		var position = 0
		for index in chosen {
			let match = offsets[index]
			output.append(contentsOf: bytes[position..<match.start])
			output.append(contentsOf: replaceBytes)
			regions.append(Region(start: match.start, oldLength: match.end - match.start, newLength: replaceBytes.count))
			position = match.end
		}
		output.append(contentsOf: bytes[position...])
		return Outcome(text: String(decoding: output, as: UTF8.self), regions: regions)
	}

	private static func lineNumber(ofUTF8Offset offset: Int, in text: String) -> Int {
		var line = 1
		var previous: UInt8 = 0
		for byte in text.utf8.prefix(offset) {
			if byte == UInt8(ascii: "\n") {
				if previous != UInt8(ascii: "\r") { line += 1 }
			} else if byte == UInt8(ascii: "\r") {
				line += 1
			}
			previous = byte
		}
		return line
	}

	// MARK: - Whitespace-lenient

	private static func applyWhitespaceLenient(
		search: String,
		replace: String,
		replaceAll: Bool,
		to text: String,
		path: String,
		cursor: Int?
	) throws -> Outcome {
		let notFound = replaceAll
			? "search text not found in file (no literal matches for replace_all, and no block of lines matches it when indentation and trailing whitespace are ignored)"
			: "search block not found in file (no exact match, and no block of lines matches it when indentation and trailing whitespace are ignored)"

		let fileLines = String.splitContentPreservingAllLineEndings(text)
		let fileKeys = fileLines.map { lineMatchKey($0.line) }
		var searchLines = String.splitContentPreservingAllLineEndings(search).map(\.line)
		var replaceLines = String.splitContentPreservingAllLineEndings(replace).map(\.line)

		var searchKeys = searchLines.map(lineMatchKey)
		guard searchKeys.contains(where: { !$0.isEmpty }) else {
			throw ApplyEditsError.invalidParams(notFound)
		}
		var starts = matchStarts(of: searchKeys, in: fileKeys)

		if starts.isEmpty,
		   String.shouldPromoteLeadingEscapedTabs(path: path, searchRaw: search, replaceRaw: replace),
		   searchLines.contains(where: hasLeadingEscapedTab) {
			let promotedSearch = searchLines.map(promoteLeadingEscapedTabs)
			let promotedKeys = promotedSearch.map(lineMatchKey)
			let promotedStarts = matchStarts(of: promotedKeys, in: fileKeys)
			if !promotedStarts.isEmpty {
				searchLines = promotedSearch
				searchKeys = promotedKeys
				replaceLines = replaceLines.map(promoteLeadingEscapedTabs)
				starts = promotedStarts
			}
		}

		guard !starts.isEmpty else {
			throw ApplyEditsError.invalidParams(notFound)
		}

		// Keep only the candidates whose indentation structure agrees.
		var transforms: [Int: IndentTransform] = [:]
		for start in starts {
			if let transform = IndentTransform(
				searchLines: searchLines,
				searchKeys: searchKeys,
				matchedLines: fileLines[start..<(start + searchLines.count)].map(\.line)
			) {
				transforms[start] = transform
			}
		}
		let structurallyMismatched = starts.filter { transforms[$0] == nil }
		starts = starts.filter { transforms[$0] != nil }
		guard !starts.isEmpty else {
			let lines = structurallyMismatched.prefix(5).map { String($0 + 1) }.joined(separator: ", ")
			throw ApplyEditsError.invalidParams(
				"\(notFound): lines with this text exist (line \(lines)) but their relative indentation differs from the search's, so replacing them would change the file's structure. Copy the block with its exact indentation."
			)
		}

		var lineOffsets: [Int] = []
		lineOffsets.reserveCapacity(fileLines.count + 1)
		var runningOffset = 0
		for entry in fileLines {
			lineOffsets.append(runningOffset)
			runningOffset += entry.line.utf8.count + entry.ending.utf8.count
		}
		lineOffsets.append(runningOffset)

		let blockLength = searchLines.count
		let chosen: [Int]
		if replaceAll {
			var picked: [Int] = []
			for start in starts where picked.last.map({ start >= $0 + blockLength }) ?? true {
				picked.append(start)
			}
			chosen = picked
		} else if let cursor {
			guard let first = starts.first(where: { lineOffsets[$0] >= cursor }) else {
				throw ApplyEditsError.invalidParams(notFound)
			}
			chosen = [first]
		} else if starts.count > 1 {
			let lines = starts.map { String($0 + 1) }.joined(separator: ", ")
			throw ApplyEditsError.invalidParams(
				"Search block matches multiple locations when whitespace is ignored (lines \(lines)). Please make the block more specific or use replace_all=true."
			)
		} else {
			chosen = starts
		}

		let lineEnding = dominantEnding(of: fileLines)
		var indentStyle: String?
		func fileIndentStyle() -> String {
			if let indentStyle { return indentStyle }
			let style = String.detectIndentationTypeFromLines(fileLines.map(\.line)).type
			indentStyle = style
			return style
		}

		var output = ""
		output.reserveCapacity(text.utf8.count + replace.utf8.count * chosen.count)
		var regions: [Region] = []
		var nextLine = 0
		for start in chosen {
			for entry in fileLines[nextLine..<start] {
				output += entry.line
				output += entry.ending
			}
			let end = start + blockLength
			let matched = fileLines[start..<end].map(\.line)
			let lines = replacementLines(
				replaceLines,
				transform: transforms[start]!,
				matchedLines: matched,
				fileIndentStyle: fileIndentStyle
			)

			var regionStart = lineOffsets[start]
			var oldLength = lineOffsets[end] - lineOffsets[start]
			let replacement: String
			if lines.isEmpty {
				replacement = ""
				// Deleting the file's last lines: the line before them becomes
				// the last line and must not gain a final ending it never had.
				if end == fileLines.count, fileLines[end - 1].ending.isEmpty, start > 0 {
					let previousEnding = fileLines[start - 1].ending
					output = String(decoding: output.utf8.dropLast(previousEnding.utf8.count), as: UTF8.self)
					regionStart -= previousEnding.utf8.count
					oldLength += previousEnding.utf8.count
				}
			} else {
				replacement = lines.joined(separator: lineEnding) + fileLines[end - 1].ending
			}
			output += replacement
			regions.append(Region(start: regionStart, oldLength: oldLength, newLength: replacement.utf8.count))
			nextLine = end
		}
		for entry in fileLines[nextLine...] {
			output += entry.line
			output += entry.ending
		}
		return Outcome(text: output, regions: regions)
	}

	private static func matchStarts(of searchKeys: [String], in fileKeys: [String]) -> [Int] {
		let count = searchKeys.count
		guard count > 0, count <= fileKeys.count else { return [] }
		var starts: [Int] = []
		for start in 0...(fileKeys.count - count) {
			var matches = true
			for offset in 0..<count where fileKeys[start + offset] != searchKeys[offset] {
				matches = false
				break
			}
			if matches { starts.append(start) }
		}
		return starts
	}

	/// How the search's indentation maps onto the matched file lines:
	/// `fileWidth = offset + scale × searchWidth` for every non-blank line
	/// (widths in columns, a tab counting 4). One distinct search width
	/// allows a pure shift; two or more fix a positive scale (a uniform
	/// change of indent unit, between ¼ and 4) that every line must satisfy.
	/// Anything else — a line nested deeper or shallower in the search than
	/// the file's relative structure — has no transform.
	struct IndentTransform {
		let offset: Int
		/// scale = scaleNumerator / scaleDenominator, kept exact.
		let scaleNumerator: Int
		let scaleDenominator: Int
		/// Search width → the matched line's exact leading whitespace.
		let anchors: [Int: Substring]
		/// Every non-blank search line has exactly its file line's indentation.
		let isIdentity: Bool

		init?(searchLines: [String], searchKeys: [String], matchedLines: [String]) {
			var pairs: [(search: Int, file: Int)] = []
			var anchors: [Int: Substring] = [:]
			var identical = true
			for index in searchLines.indices where !searchKeys[index].isEmpty {
				let searchIndent = TextEditApplier.leadingWhitespace(of: searchLines[index])
				let fileIndent = TextEditApplier.leadingWhitespace(of: matchedLines[index])
				if searchIndent != fileIndent { identical = false }
				let searchWidth = TextEditApplier.indentationWidth(searchIndent)
				if anchors[searchWidth] == nil { anchors[searchWidth] = fileIndent }
				pairs.append((searchWidth, TextEditApplier.indentationWidth(fileIndent)))
			}
			guard let first = pairs.first else { return nil }

			var numerator = 1
			var denominator = 1
			if let second = pairs.first(where: { $0.search != first.search }) {
				numerator = second.file - first.file
				denominator = second.search - first.search
				if denominator < 0 {
					numerator = -numerator
					denominator = -denominator
				}
				// Order-preserving and a plausible unit ratio (¼ … 4).
				guard numerator > 0, numerator * 4 >= denominator, numerator <= denominator * 4 else { return nil }
			}
			for pair in pairs {
				// (file - file₀) · d == n · (search - search₀)
				guard (pair.file - first.file) * denominator == numerator * (pair.search - first.search) else {
					return nil
				}
			}
			self.scaleNumerator = numerator
			self.scaleDenominator = denominator
			// offset · d = file₀ · d − n · search₀ (kept scaled to stay exact)
			self.offset = first.file * denominator - numerator * first.search
			self.anchors = anchors
			self.isIdentity = identical
		}

		func fileWidth(forSearchWidth width: Int) -> Int {
			let scaled = offset + scaleNumerator * width
			// Round half up, never below zero.
			return max(0, (2 * scaled + scaleDenominator) / (2 * scaleDenominator))
		}
	}

	/// The replacement lines to write for one lenient match: as given when
	/// the search's indentation is the file's, otherwise each line's leading
	/// whitespace re-based by the match's transform — a width the search
	/// used takes the matched line's exact whitespace, any other width is
	/// written in the file's indentation style. Only leading whitespace
	/// changes.
	private static func replacementLines(
		_ replaceLines: [String],
		transform: IndentTransform,
		matchedLines: [String],
		fileIndentStyle: () -> String
	) -> [String] {
		guard !replaceLines.isEmpty else { return [] }
		if transform.isIdentity {
			return replaceLines
		}
		return replaceLines.map { line in
			let indent = leadingWhitespace(of: line)
			let content = line.dropFirst(indent.count)
			if content.isEmpty {
				return line
			}
			let width = indentationWidth(indent)
			if let exact = transform.anchors[width] {
				return String(exact) + content
			}
			return indentation(ofWidth: transform.fileWidth(forSearchWidth: width), style: fileIndentStyle()) + content
		}
	}

	private static let tabWidth = 4

	fileprivate static func indentationWidth<S: StringProtocol>(_ whitespace: S) -> Int {
		whitespace.reduce(0) { $0 + ($1 == "\t" ? tabWidth : 1) }
	}

	private static func indentation(ofWidth width: Int, style: String) -> String {
		if style == "t" {
			return String(repeating: "\t", count: width / tabWidth) + String(repeating: " ", count: width % tabWidth)
		}
		return String(repeating: " ", count: width)
	}

	fileprivate static func leadingWhitespace(of line: String) -> Substring {
		line.prefix { $0 == " " || $0 == "\t" }
	}

	private static func hasLeadingEscapedTab(_ line: String) -> Bool {
		let content = line.drop { $0 == " " || $0 == "\t" }
		return content.hasPrefix("\\t") || content.hasPrefix("\\u0009")
	}

	/// `  \t\tfoo` (with literal backslash-t escapes) → `  ` + two tabs + `foo`.
	private static func promoteLeadingEscapedTabs(_ line: String) -> String {
		var indentation = String(leadingWhitespace(of: line))
		var content = line.dropFirst(indentation.count)
		while true {
			if content.hasPrefix("\\t") {
				content = content.dropFirst(2)
			} else if content.hasPrefix("\\u0009") {
				content = content.dropFirst(6)
			} else {
				break
			}
			indentation.append("\t")
		}
		return indentation + content
	}

	private static func dominantEnding(of lines: [(line: String, ending: String)]) -> String {
		var counts: [String: Int] = [:]
		var last = "\n"
		for entry in lines where !entry.ending.isEmpty {
			counts[entry.ending, default: 0] += 1
			last = entry.ending
		}
		let best = counts.values.max() ?? 0
		let leaders = counts.filter { $0.value == best }.map(\.key)
		return leaders.count == 1 ? leaders[0] : last
	}
}

/// Diff chunks shown for an edit: the original and the updated text, both
/// indentation-encoded with the original's detected style, diffed line by
/// line. Line endings are not part of the comparison.
enum ApplyEditsDisplayDiff {
	static func chunks(original: String, updated: String) -> [DiffChunk] {
		let (originalLines, _) = String.splitContentPreservingLineEndings(original)
		let (indentType, _) = String.detectIndentationTypeFromLines(originalLines)
		let encodedOriginal = originalLines.map {
			String.encodeIndentationWithConversion($0, desiredIndentationType: indentType)
		}
		let encodedUpdated = String.splitContentPreservingLineEndings(updated).0.map {
			String.encodeIndentationWithConversion($0, desiredIndentationType: indentType)
		}
		return DiffGenerationUtility.generateRewriteDiff(fileContent: encodedOriginal, newContent: encodedUpdated)
	}
}
