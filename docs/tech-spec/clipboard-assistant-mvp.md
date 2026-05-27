# Clipboard Assistant MVP Technical Contract

## Scope

This document freezes T1 only: the shared model and protocol surface for macOS clipboard assistant work. It deliberately does not implement:

- Clipboard polling.
- Global hotkey registration.
- Menu bar status item.
- Overlay window rendering.
- Accessibility permission prompt.
- CGEvent based paste.

Those belong to T2-T5 after `PasteCore` compiles in the real repository.

## Module

`PasteCore` is a Foundation-first Swift module. It avoids AppKit and SwiftUI so tests can run quickly and parallel tasks can mock system behavior.

```text
Sources/PasteCore/
  ClipboardKind.swift
  ClipboardPayload.swift
  ClipboardSignature.swift
  ClipboardItem.swift
  PasteTarget.swift
  PasteResult.swift
  SystemContracts.swift
```

## Core Models

| Type | Responsibility |
| --- | --- |
| `ClipboardKind` | Stable content kind enum: text, url, image, file, unknown |
| `ClipboardPayload` | Pasteboard payload represented as `typeIdentifier + Data` |
| `ClipboardItem` | History item shared by collector, store, overlay, and paste coordinator |
| `PasteTarget` | Frontmost app identity captured before overlay activation |
| `PasteResult` | Paste outcome: pasted, copied-only fallback, or hard failure |
| `ClipboardSignature` | Deterministic signature generation for duplicate detection |

`ClipboardPayload` intentionally stores pasteboard type identifiers as strings instead of `NSPasteboard.PasteboardType`. That keeps the core target framework-neutral; the AppKit adapter can translate to and from native pasteboard types in T3/T5.

## Protocol Contracts

| Protocol | Future owner | Purpose |
| --- | --- | --- |
| `HotKeyManaging` | T2 | Register and unregister global shortcut handling |
| `ClipboardMonitoring` | T3 | Start/stop pasteboard change monitoring |
| `ClipboardClassifying` | T3 | Convert raw payloads into `ClipboardItem` |
| `ClipboardHistoryProviding` | T3/T6 | Own ordered history state |
| `OverlayPresenting` | T4 | Show/hide the bottom overlay using shared items |
| `FocusTracking` | T5 | Return target app captured before overlay activation |
| `PasteCoordinating` | T5 | Write selected item and perform or downgrade paste |
| `PermissionPresenting` | T5 | Check and open Accessibility permission flow |

## Signature Rules

`ClipboardSignature.make(kind:payloads:)` is frozen with these rules:

- Prefix with `ClipboardKind.rawValue`.
- Sort payloads by `typeIdentifier`.
- Hash kind, payload type identifiers, and payload bytes with SHA-256.
- Return `<kind>:<hex digest>`.

This keeps duplicate detection stable even if adapter code receives equivalent pasteboard payloads in a different order.

## Test Coverage

`Tests/PasteCoreTests/ClipboardContractsTests.swift` currently verifies:

- Signatures are stable across payload ordering.
- `ClipboardItem` carries renderable metadata and paste payloads.
- `PasteCoordinating` can be mocked by downstream parallel tasks.

Run:

```bash
swift test
```

## Non-Goals For T1

- No persistent history store.
- No UI.
- No AppKit window code.
- No Carbon hotkey code.
- No `NSPasteboard` reads or writes.
- No Accessibility authorization dialog.
- No installation, signing, or notarization configuration.
