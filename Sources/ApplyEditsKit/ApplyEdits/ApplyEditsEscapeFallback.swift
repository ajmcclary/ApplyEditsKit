import Foundation

public struct ApplyEditsEscapeFallback {
	private let decoder: EscapeDecoder
	private let mode: EscapeDecodingMode

	public init(decoder: EscapeDecoder = EscapeDecoder(), mode: EscapeDecodingMode = .cStyle) {
		self.decoder = decoder
		self.mode = mode
	}

	public func resolveSingle(search: String, replace: String, in originalText: String) -> (search: String, replace: String, usedFallback: Bool) {
		resolve(search: search, replace: replace, in: originalText)
	}

	public func resolveBatch(edits: [ApplyEditsOperation], in originalText: String) -> (edits: [ApplyEditsOperation], usedFallbackCount: Int) {
		var fallbackCount = 0
		let resolvedEdits = edits.map { edit in
			let resolved = resolve(search: edit.search, replace: edit.replace, in: originalText)
			if resolved.usedFallback {
				fallbackCount += 1
			}
			if resolved.search == edit.search && resolved.replace == edit.replace {
				return edit
			}
			return ApplyEditsOperation(search: resolved.search, replace: resolved.replace, replaceAll: edit.replaceAll)
		}
		return (resolvedEdits, fallbackCount)
	}

	private func resolve(search: String, replace: String, in originalText: String) -> (search: String, replace: String, usedFallback: Bool) {
		guard !search.isEmpty else {
			return (search, replace, false)
		}
		if originalText.contains(search) {
			return (search, replace, false)
		}
		guard search.contains("\\") else {
			return (search, replace, false)
		}

		let decodedSearch = decoder.decode(search, mode: mode)
		guard decodedSearch != search else {
			return (search, replace, false)
		}
		guard originalText.contains(decodedSearch) else {
			return (search, replace, false)
		}

		return (decodedSearch, Self.decodeReplacement(replace, likeSearch: search), true)
	}

	/// The search matched only after decoding, so the payload was probably
	/// escaped once too often. The replacement is decoded under the same
	/// assumption, but only as far as the search gives evidence for it:
	/// - `\n`, `\r`, `\t` are decoded only if the search used that escape
	///   (a `\tau` or `\temp` in the replacement survives a `\n` search);
	/// - `\\` and `\"` are decoded, since an over-escaped payload writes every
	///   literal backslash and quote that way;
	/// - a replacement that already contains a real newline, carriage return
	///   or tab for an escape the search used was evidently not over-escaped
	///   and is used as given.
	/// A single-line replacement such as `print("\n")` after a `\n` search
	/// stays ambiguous and is read as over-escaped (one newline).
	static func decodeReplacement(_ replace: String, likeSearch search: String) -> String {
		let kinds = escapeKinds(in: search)
		let scalars = replace.unicodeScalars
		if (kinds.contains("n") && scalars.contains("\n"))
			|| (kinds.contains("r") && scalars.contains("\r"))
			|| (kinds.contains("t") && scalars.contains("\t")) {
			return replace
		}
		var decodable: Set<Character> = ["\\", "\""]
		decodable.formUnion(kinds.intersection(["n", "r", "t"]))

		var output = ""
		output.reserveCapacity(replace.utf8.count)
		var iterator = Array(replace).makeIterator()
		while let character = iterator.next() {
			guard character == "\\" else {
				output.append(character)
				continue
			}
			guard let escaped = iterator.next() else {
				output.append(character)
				break
			}
			guard decodable.contains(escaped) else {
				output.append(character)
				output.append(escaped)
				continue
			}
			switch escaped {
			case "n": output.append("\n")
			case "r": output.append("\r")
			case "t": output.append("\t")
			default: output.append(escaped)
			}
		}
		return output
	}

	/// Escape letters (`n`, `r`, `t`, `\\`, `"`) that follow a backslash in
	/// `text`, reading `\\` as one escape.
	private static func escapeKinds(in text: String) -> Set<Character> {
		var kinds: Set<Character> = []
		var iterator = Array(text).makeIterator()
		while let character = iterator.next() {
			guard character == "\\", let escaped = iterator.next() else { continue }
			if ["n", "r", "t", "\\", "\""].contains(escaped) {
				kinds.insert(escaped)
			}
		}
		return kinds
	}
}
