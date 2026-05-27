# Clipboard Assistant MVP Task Boundary

## T0 Result: Repository And Build Mapping

The configured repository is `https://github.com/Errorrrrr/paste`.

Current workspace checkout status:

| Check | Result |
| --- | --- |
| `multica repo checkout https://github.com/Errorrrrr/paste` | Failed: bare cache has no usable refs |
| Bare cache HEAD | `refs/heads/main` |
| Bare cache refs | Empty |
| Remote GitHub page | Empty repository, no committed branch visible |
| Local workspace Git status | Not a git repository |

Conclusion: there is no recoverable project tree in this workspace yet. T0 cannot map existing code style, target names, app bundle configuration, or build scripts from an existing repo. The safest bootstrap mapping is a Swift Package containing only T1 shared contracts, so downstream T2-T5 work can depend on a compiled model/protocol surface after the real repository is initialized.

## Temporary Build Path

Until `Errorrrrr/paste` has an initial branch, the T1 contract artifact lives at the workspace root:

| Purpose | Path |
| --- | --- |
| SwiftPM manifest | `Package.swift` |
| Core contracts target | `Sources/PasteCore/` |
| Contract tests | `Tests/PasteCoreTests/` |
| Build and test command | `swift test` |

Confirmed local toolchain:

```text
Apple Swift 6.3.2, target arm64-apple-macosx26.0
```

## Repository Initialization Mapping

When the GitHub repo has a real `main` branch, copy this bootstrap package into the repo root unless an Xcode project already exists by then.

| Current path | Repo path after initialization | Notes |
| --- | --- | --- |
| `Package.swift` | `Package.swift` or app workspace package dependency | Keep `PasteCore` as the shared contract module |
| `Sources/PasteCore/ClipboardKind.swift` | `Sources/PasteCore/ClipboardKind.swift` | Shared type tags for UI, monitor, and paste layers |
| `Sources/PasteCore/ClipboardPayload.swift` | `Sources/PasteCore/ClipboardPayload.swift` | Framework-neutral pasteboard payload wrapper |
| `Sources/PasteCore/ClipboardSignature.swift` | `Sources/PasteCore/ClipboardSignature.swift` | Deterministic duplicate signature helper |
| `Sources/PasteCore/ClipboardItem.swift` | `Sources/PasteCore/ClipboardItem.swift` | Renderable and pasteable history item |
| `Sources/PasteCore/PasteTarget.swift` | `Sources/PasteCore/PasteTarget.swift` | Captured target app identity |
| `Sources/PasteCore/PasteResult.swift` | `Sources/PasteCore/PasteResult.swift` | Paste success, fallback, and failure result contract |
| `Sources/PasteCore/SystemContracts.swift` | `Sources/PasteCore/SystemContracts.swift` | Mockable boundaries for T2-T5 |
| `Tests/PasteCoreTests/ClipboardContractsTests.swift` | `Tests/PasteCoreTests/ClipboardContractsTests.swift` | Compile and behavior guard for T1 |

If the actual repo is later initialized as an Xcode app instead of a SwiftPM-first layout, keep `PasteCore` as either:

1. A local Swift package inside the Xcode workspace, or
2. A framework target named `PasteCore`.

Do not duplicate these model types inside App, Overlay, Clipboard, or Paste implementation targets.

## Frozen MVP Defaults

| Decision | Frozen default for T1 |
| --- | --- |
| App platform | Native macOS for Apple Silicon |
| Language | Swift |
| Core contract module | `PasteCore` |
| System implementation layer | Future AppKit/SwiftUI app target, not part of T1 |
| Menu entry | macOS menu bar status item |
| Dock icon | Hidden by default unless product confirms otherwise |
| History storage | In memory, max 50 items |
| Default hotkey | `Cmd+Option+V` |
| Display order | Newest item first / leftmost |
| Permission fallback | If Accessibility is not trusted, copy only and do not synthesize paste |
| Supported MVP kinds | `text`, `url`, `image`, `file`, `unknown` |

## T1 Completion Gate

T1 is considered ready for parallel T2-T5 work when all of the following are true:

- `swift test` passes for `PasteCore`.
- T2-T5 agree to import `PasteCore` instead of redefining models.
- Any real app target wires implementations behind the protocols in `SystemContracts.swift`.
- No system behavior implementation exists inside `PasteCore`; it remains model and boundary only.

T2-T5 should remain blocked until the real repository has an initial branch or these bootstrap files are explicitly accepted as the initial repo contents.
