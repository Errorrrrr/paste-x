# macOS System Capability Boundary

This contract defines how later implementation tasks may interact with macOS-specific behavior while keeping the shared `PasteCore` module stable.

## Ownership

| Capability | Protocol | Implementation phase |
| --- | --- | --- |
| Menu bar and hotkey entry | `HotKeyManaging` plus app shell code | T2 |
| Clipboard polling and classification | `ClipboardMonitoring`, `ClipboardClassifying` | T3 |
| Bottom overlay rendering | `OverlayPresenting` | T4 |
| Target app tracking | `FocusTracking` | T5 |
| Paste execution and fallback | `PasteCoordinating`, `PermissionPresenting` | T5 |

## Rules

- Implementations may import AppKit, Carbon, ApplicationServices, or SwiftUI.
- `PasteCore` must not import AppKit, Carbon, ApplicationServices, or SwiftUI.
- Implementation tasks must exchange `ClipboardItem`, `PasteTarget`, and `PasteResult`.
- If Accessibility permission is missing, implementations must return `.copiedOnly(reason: .accessibilityNotTrusted)`.
- If target activation or event posting fails, implementations must preserve the selected item on the general pasteboard and return a copied-only fallback where possible.
- System adapters must not create new model enums for clipboard kinds or paste outcomes.

## Default Sequence For Integration

1. Capture `PasteTarget` before the overlay becomes key.
2. Resolve selected `ClipboardItem`.
3. Write `ClipboardItem.payloads` to the general pasteboard.
4. Hide the overlay.
5. Reactivate `PasteTarget`.
6. If Accessibility is trusted, synthesize `Cmd+V`.
7. If any required step is unavailable, return a `PasteResult` fallback instead of crashing.
