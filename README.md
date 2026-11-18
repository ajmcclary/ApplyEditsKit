# ApplyEditsKit

Applies model-proposed text edits (search/replace, batches of them, or a whole-file rewrite) to
files your application owns, and produces the diffs to show for them.

An AI coding tool receives edits as "replace this text with that text" and has to land them
precisely: find the right occurrence even when the model's whitespace is a little off, refuse
when the text is not there or is ambiguous, keep the file's own line endings, report which edits
in a batch failed, and render a reviewable diff. This package does that work as a pure engine.
It never touches the file system itself; all reads and writes go through a protocol your
application implements, so path policy, sandboxing and storage stay in your hands.

## Ports: what the host implements

"Port-based" means the engine talks to the outside world only through protocols:

- `FileEditHost` — the one port every host implements. Three methods:
  `fileExists(path:)`, `readText(path:)` and `writeText(path:content:overwrite:)`. Back it with
  `FileManager`, a sandbox, an editor buffer or an in-memory dictionary.
- `DiffChunkGenerator`, `DiffChunkApplier`, `UnifiedDiffRendering` — optional seams inside
  `ApplyEditsEngine` for replacing how edits are matched, applied or rendered.
  `ApplyEditsEngine.default` wires up `DefaultDiffChunkGenerator`, `DefaultDiffChunkApplier` and
  `DefaultUnifiedDiffRenderer`, which is what most hosts want.

## What's inside

The `ApplyEditsKit` product makes two modules importable:

| Module | Role |
|---|---|
| `ApplyEditsKit` | The Swift engine, service, value models and diff machinery. |
| `ApplyEditsCSupport` | C helpers (`repo_*`) for indentation encoding, escaping, line splitting, canonical keys, hashing and fuzzy matching. |

Key public types in `ApplyEditsKit`:

- `ApplyEditsService` — reads through a `FileEditHost`, computes the edit, and writes it.
  `run(_:)` does both; `prepare(_:)` then `commit(_:)` lets you review in between.
- `ApplyEditsEngine` — the host-free core: `apply(request:to:)` turns a request plus the
  original text into a result, with no I/O.
- `ApplyEditsRequest` / `ApplyEditsMode` / `ApplyEditsOperation` — a path plus `.single`,
  `.batch` or `.rewrite(newText:onMissing:)`.
- `ApplyEditsResult` — updated text, `DiffChunk`s, optional unified diffs, stats,
  requested/applied counts, a `success`/`partial`/`failed` status and per-edit `EditOutcome`s.
- `ApplyEditsPreparedEdit` / `ApplyEditsBaseIdentity` — a computed edit tagged with the SHA-256
  and length of the text it was computed from.
- `ApplyEditsFileChangedError` — thrown by `commit` when the file changed, was deleted or
  appeared since `prepare`; nothing is written.
- `ApplyEditsError` — `invalidParams` / `internalError` for bad requests.
- `UnifiedDiffGenerator`, `DiffChunk`, `DiffLine` — deterministic diff values and unified-diff
  rendering, usable on their own.
- `EscapeDecoder`, `ApplyEditsEscapeFallback`, `IndentCorrectionUtility` — recovery for
  over-escaped model output and indentation drift.
- `EditFlowPerf` — signpost instrumentation, compiled in only for `DEBUG` builds or with the
  `EDIT_FLOW_PERF` compilation condition.

## When to use it

- You are building an agent, MCP tool or editor command that applies search/replace edits from a
  language model and want exact, whitespace-tolerant matching that fails loudly instead of
  editing the wrong lines.
- You need byte-faithful results: untouched lines keep their own line endings.
- You want a review step: compute and show a diff, then write only if the file is unchanged.

## When not to

- You only need a general text-diff library: `UnifiedDiffGenerator` works standalone, but the
  rest of the package is shaped around model edits.
- File-tree browsing, ignore rules, watching and path search belong to
  [WorkspaceKit](https://github.com/ajmcclary/WorkspaceKit); an interactive editor view belongs to
  [CodeEditorKit](https://github.com/ajmcclary/CodeEditorKit). The tool names and authorization
  vocabulary for serving an `apply_edits` tool over MCP are in
  [MCPContractsKit](https://github.com/ajmcclary/MCPContractsKit).
- Out of scope: concrete file-system access and sandbox or workspace authorization policy (your
  `FileEditHost` decides), MCP server orchestration, model provider transports, prompts,
  persistence, settings and UI.

## Installation

```swift
dependencies: [
    // 0.1.0-beta.5 is a prerelease identifier; SwiftPM only resolves prerelease tags when the
    // lower bound itself names one.
    .package(url: "https://github.com/ajmcclary/ApplyEditsKit.git", .upToNextMinor(from: "0.1.0-beta.5"))
],
targets: [
    .target(name: "MyTool", dependencies: [
        .product(name: "ApplyEditsKit", package: "ApplyEditsKit")
    ])
]
```

## Usage

```swift
import ApplyEditsKit
import Foundation

// The host decides where text lives and who may touch it. This one keeps it in memory.
actor InMemoryHost: FileEditHost {
    private var files: [String: String]
    init(files: [String: String]) { self.files = files }

    func fileExists(path: String) async -> Bool { files[path] != nil }
    func readText(path: String) async throws -> String {
        guard let text = files[path] else { throw CocoaError(.fileNoSuchFile) }
        return text
    }
    func writeText(path: String, content: String, overwrite: Bool) async throws {
        if !overwrite, files[path] != nil { throw CocoaError(.fileWriteFileExists) }
        files[path] = content
    }
}

let host = InMemoryHost(files: ["Sources/App.swift": "let greeting = \"Hello\"\n"])
let service = ApplyEditsService(engine: .default, host: host)
let request = ApplyEditsRequest(
    path: "Sources/App.swift",
    mode: .single(search: "\"Hello\"", replace: "\"Hi\"", replaceAll: false),
    verbose: true)

let prepared = try await service.prepare(request)    // computes, writes nothing
print(prepared.result.unifiedDiff ?? "")              // unified diff (verbose: true)
do {
    let result = try await service.commit(prepared)  // writes only if the file is unchanged
    print(result.status, result.editsApplied)         // success 1
} catch let error as ApplyEditsFileChangedError {
    print(error.localizedDescription)                 // nothing was written
}
```

Without a host, `try await ApplyEditsEngine.default.apply(request: request, to: text)` returns the
same `ApplyEditsResult` for a string you already hold.

## Requirements

- Swift tools version 6.0, Swift 6 language mode with strict concurrency.
- **macOS 27.0 only.** The package depends on WorkspaceKit, whose FSEvents-backed file-system
  module does not build for iOS, so no iOS floor is declared.
- Dependencies: [WorkspaceKit](https://github.com/ajmcclary/WorkspaceKit)
  (`.upToNextMinor(from: "0.1.0-beta.15")`). The edge is required, not incidental: four
  similarity functions declared in `ApplyEditsCSupport` (`repo_levenshtein_distance`,
  `repo_dice_coefficient`, `repo_longest_common_subsequence`, `repo_similarity_score`) are
  defined in WorkspaceKit's `WorkspaceKitCSupport` and link in through it. Do not link another
  copy of those symbols alongside this package. No third-party dependencies.

## Stability

Pre-1.0 (`0.x` beta): the public API may change between minor versions, so pin with
`.upToNextMinor`.

## Development

```sh
swift build
swift test
```

The suite is fast; the edit engine is exercised against an in-memory `FileEditHost`.

## Origin

Extracted from the RepoPrompt app (Apache-2.0).

## License

Apache License 2.0 — see [LICENSE](LICENSE).
