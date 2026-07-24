// swift-tools-version: 6.0
import PackageDescription

// ApplyEditsKit — port-based edit application and its deterministic
// diff/matching machinery.
//
// Promoted verbatim out of RepoPrompt's internal RepoPromptCore package
// (its ApplyEditsCore + ApplyEditsCSupport targets) as the third
// extraction of the migrate.md package map. RepoPromptCore's
// ApplyEditsCore target is now an @_exported re-export shim over this
// package (the AgentRuntimeKit / PromptAssemblyKit promotion precedent).
//
// Scope: the port-free apply_edits engine and service (ApplyEditsEngine,
// ApplyEditsService) with their request/result value models and error
// vocabulary; the engine's seam protocols (DiffChunkGenerator,
// DiffChunkApplier, UnifiedDiffRendering) plus the narrow FileEditHost
// file-I/O port the host application adapts; the deterministic diffing
// machinery (DiffChunk/DiffLine, DiffGenerationUtility, DiffApplicator,
// DiffBatchGenerator, DiffParserUtils, UnifiedDiffGenerator, FileChange/
// ChangeManager/ChangeApplier, FileAction); escape decoding and
// indentation correction (EscapeDecoder, ApplyEditsEscapeFallback,
// IndentCorrectionUtility, OptimalLineFinderUtility); the EditFlowPerf
// signpost instrumentation; and the ApplyEditsCSupport C target (the
// repo_* string helpers the Swift String bridge rides). Deliberately OUT
// of scope: SwiftUI/AppKit and view models, workspace authorization/
// sandbox policy and concrete filesystem ownership (WorkspaceFileEditHost
// and SandboxFileEditHost stay app-side behind the FileEditHost port),
// MCP server orchestration, provider transports, prompts, persistence,
// and app settings.
//
// One package dependency: WorkspaceKit. The ApplyEditsCSupport C target
// declares repo_levenshtein_distance / repo_dice_coefficient /
// repo_longest_common_subsequence / repo_similarity_score in its public
// header, but their definitions live in WorkspaceKit's WorkspaceKitCSupport
// (repo_similarity.c — WorkspaceKit adoption slice 4); the symbols link in
// via the product dependency. Re-defining them here would create duplicate
// link symbols for any consumer that links both packages, so the edge is
// load-bearing, not incidental. Swift 5 language mode keeps the moved code
// byte-behaviorally identical (AgentRuntimeKit / PromptAssemblyKit /
// RepoPromptCore promoted-target precedent).
//
// Platform floor: macOS 14 ONLY — a deliberate divergence from the
// AgentRuntimeKit / PromptAssemblyKit macOS 14 + iOS 17 precedent. Those
// kits are dependency-free; this one links WorkspaceKit's umbrella
// product, whose WorkspaceFileSystem target is FSEvents-backed and does
// not compile for iOS (verified 2026-07-24: a generic/platform=iOS build
// fails inside WorkspaceKit, not in this package). Claiming an iOS floor
// here would be unprovable; RepoPromptCore, the only consumer, is
// macOS-only anyway.
let package = Package(
    name: "ApplyEditsKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Bundles both targets: consumers import ApplyEditsKit for the
        // Swift engine and may import ApplyEditsCSupport directly for the
        // repo_* C declarations (RepoPrompt's remaining direct C callers
        // do exactly that through its CoreExports umbrella).
        .library(name: "ApplyEditsKit", targets: ["ApplyEditsKit", "ApplyEditsCSupport"])
    ],
    dependencies: [
        // Supplies the repo_* similarity-function definitions linked by
        // ApplyEditsCSupport (see header comment). Prerelease lower bound
        // named explicitly (SwiftPM only resolves prerelease tags when the
        // requirement names one — ProcessKit rule).
        .package(url: "https://github.com/ajmcclary/WorkspaceKit.git", .upToNextMinor(from: "0.1.0-beta.1"))
    ],
    targets: [
        .target(
            name: "ApplyEditsKit",
            dependencies: ["ApplyEditsCSupport"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // High-performance C string helpers (repo_* — indentation
        // encode/decode, escaping, line splitting, canonical keys,
        // fnv1a hashing, fuzzy space matching, chat-content parsing).
        // Four similarity functions are declared here but defined in
        // WorkspaceKitCSupport; the WorkspaceKit product dependency
        // links them in.
        .target(
            name: "ApplyEditsCSupport",
            dependencies: [.product(name: "WorkspaceKit", package: "WorkspaceKit")]
        ),
        .testTarget(
            name: "ApplyEditsKitTests",
            dependencies: ["ApplyEditsKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
