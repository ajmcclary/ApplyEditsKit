import Foundation
@testable import ApplyEditsKit

actor InMemoryFileEditHost: FileEditHost {
	struct HostError: Error {}

	private var files: [String: String]
	private(set) var writes: [(path: String, overwrite: Bool, content: String)] = []

	init(files: [String: String] = [:]) {
		self.files = files
	}

	func fileExists(path: String) async -> Bool {
		files[path] != nil
	}

	func readText(path: String) async throws -> String {
		guard let text = files[path] else { throw HostError() }
		return text
	}

	func writeText(path: String, content: String, overwrite: Bool) async throws {
		if !overwrite, files[path] != nil { throw HostError() }
		files[path] = content
		writes.append((path: path, overwrite: overwrite, content: content))
	}

	func currentText(path: String) async -> String? {
		files[path]
	}
}
