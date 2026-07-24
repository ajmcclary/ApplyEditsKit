import XCTest

// Package-tests copy of the app test helper of the same name
// (RepoPromptTests/Helpers/MCPApplyEditsTestSupport.swift) — test targets
// can't share helpers across the package boundary.
func XCTAssertThrowsErrorAsync<T>(
	_ expression: @autoclosure () async throws -> T,
	file: StaticString = #filePath,
	line: UInt = #line,
	_ inspect: (Error) -> Void = { _ in }
) async {
	do {
		_ = try await expression()
		XCTFail("Expected error but got success", file: file, line: line)
	} catch {
		inspect(error)
	}
}
