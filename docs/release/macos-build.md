# macOS Build And First-Run Notes

This repo ships a SwiftPM executable target named `Paste` and a local macOS app bundle script.

## Build

```bash
./scripts/build-macos.sh
```

Default output:

- `dist/Paste.app`
- `dist/Paste-macos-arm64-qa-only.zip`

The script builds the `Paste` executable in release mode for `arm64`, copies `Resources/Info.plist` into the app bundle, signs the app, verifies the signature, and zips the bundle with `ditto`.

By default `SIGNING_MODE=qa`, which uses ad-hoc signing unless `CODESIGN_IDENTITY` is explicitly provided. QA mode always writes a `*-qa-only.zip` artifact so it is not confused with a distributable macOS release. That package is for local QA and internal handoff only; it is not a Gatekeeper/notarized external release artifact.

`Resources/Paste.entitlements` is intentionally empty for MVP non-sandboxed distribution. Clipboard reads and synthesized paste events are guarded by macOS TCC Accessibility consent, not by a sandbox entitlement. If the app later targets the Mac App Store, sandbox behavior needs a separate validation pass because CGEvent-based auto-paste may be constrained.

Useful overrides:

```bash
ARCH=arm64 CONFIGURATION=release ./scripts/build-macos.sh
SIGNING_MODE=qa CODESIGN_IDENTITY="Apple Development: Example Team (TEAMID)" ./scripts/build-macos.sh
SIGNING_MODE=release CODESIGN_IDENTITY="Developer ID Application: Example Team (TEAMID)" ./scripts/build-macos.sh
SKIP_CODESIGN=1 ./scripts/build-macos.sh
```

`SIGNING_MODE=release` fails unless `CODESIGN_IDENTITY` is set to a non-ad-hoc Developer ID Application identity. For Developer ID distribution, submit the generated release zip with your configured notarytool profile and staple the app before external distribution:

```bash
SIGNING_MODE=release CODESIGN_IDENTITY="Developer ID Application: Example Team (TEAMID)" ./scripts/build-macos.sh
xcrun notarytool submit dist/Paste-macos-arm64.zip --keychain-profile "<profile>" --wait
xcrun stapler staple dist/Paste.app
ditto -c -k --sequesterRsrc --keepParent dist/Paste.app dist/Paste-macos-arm64.zip
```

## Runtime Shape

- `LSUIElement` is enabled in `Resources/Info.plist`, so launch does not open a Dock icon or a main window.
- The app runs as a menu bar item using the clipboard icon.
- Left-click the menu bar item to toggle the bottom clipboard overlay.
- Right-click or Control-click the menu bar item to open a menu with `Show Clipboard History` and `Quit Paste`.
- The default global shortcut is `Cmd+Option+V`. If registration fails because of a conflict, the app keeps running and the menu bar item remains usable.

## Permissions

The app does not request Accessibility at launch. The permission path is first exercised when the user tries to paste from the overlay:

1. User selects an overlay item with Space, Return, or double-click.
2. `AccessibilityPermissionPresenter` calls `AXIsProcessTrustedWithOptions` with prompting enabled.
3. macOS shows the Accessibility consent prompt if the app is not trusted.
4. If the user grants permission, retrying the paste path can activate the captured target app and send `Cmd+V`.
5. If the user denies permission, the app keeps the selected item on the general pasteboard and returns the copied-only fallback.

Manual settings path: System Settings -> Privacy & Security -> Accessibility -> enable `Paste`.

## QA Smoke Check

1. Open `dist/Paste.app`; verify no main window or Dock icon appears and a clipboard menu bar icon is visible.
2. Copy text, a URL, an image, and a file; verify the overlay shows recent items newest-first with type markers.
3. Toggle the overlay by menu bar click and by `Cmd+Option+V`.
4. Use Space, Return, and double-click to paste into TextEdit or another text input.
5. In a clean user profile, verify the first paste attempt triggers the Accessibility path, and denial falls back to copy-only with a visible overlay message instead of silently closing.
6. Right-click the menu bar icon, choose `Quit Paste`, reopen the app, and verify the menu bar item and hotkey register again.
