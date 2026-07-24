import Foundation

/// Pure helpers (no AppKit/SwiftUI) that were previously duplicated.
public enum DiffEncodingUtils {

	/// Helper to encode arbitrary raw text into `[String]` using the same rules
	/// as `encodedOriginal(of:)` (app-side extension).
	public static func encode(_ raw:String, usesSpaces:Bool) -> [String] {
		DiffParserUtils.splitContentToLines(raw, usesSpaces)
	}
}
