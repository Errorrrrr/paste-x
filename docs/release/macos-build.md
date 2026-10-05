# macOS Build And First-Run Notes

This repo ships a SwiftPM executable product named `PasteX` and a local macOS app bundle script.

If the installed Command Line Tools cannot link the SwiftPM package manifest, use `SDK_PATH=<matching macOS SDK> ./scripts/build-macos-direct-qa.sh`. This fallback compiles the same targets directly and produces only an ad-hoc signed QA app and ZIP; it does not sign or notarize a public distribution build.

## Build

```bash
./scripts/build-macos.sh
```

Default output:

- `dist/PasteX.app`
- `dist/PasteX-macos-arm64-qa-only.zip`

The script builds the `PasteX` executable in release mode for `arm64`, copies `Resources/Info.plist` and `Resources/PasteXAppIcon.icns` into the app bundle, signs the app, verifies the signature, and zips the bundle with `ditto`.

By default `SIGNING_MODE=qa`, which uses ad-hoc signing unless `CODESIGN_IDENTITY` is explicitly provided. QA mode always writes a `*-qa-only.zip` artifact so it is not confused with a distributable macOS release. That package is for local QA and internal handoff only; it is not a Gatekeeper/notarized external release artifact. The QA build also removes older `*-qa-only*.zip` files from `dist/` before writing the new package so the handoff directory keeps only the latest test package.

`Resources/Paste.entitlements` is intentionally empty for MVP non-sandboxed distribution. Clipboard reads and synthesized paste events are guarded by macOS TCC Accessibility consent, not by a sandbox entitlement. If the app later targets the Mac App Store, sandbox behavior needs a separate validation pass because CGEvent-based auto-paste may be constrained.

Useful overrides:

```bash
ARCH=arm64 CONFIGURATION=release ./scripts/build-macos.sh
SIGNING_MODE=qa CODESIGN_IDENTITY="Apple Development: Example Team (TEAMID)" ./scripts/build-macos.sh
SIGNING_MODE=release CODESIGN_IDENTITY="Developer ID Application: Example Team (TEAMID)" NOTARY_KEYCHAIN_PROFILE="paste-notary" ./scripts/build-macos.sh
SKIP_CODESIGN=1 ./scripts/build-macos.sh
```

`SIGNING_MODE=release` fails unless `CODESIGN_IDENTITY` is set to a Developer ID Application identity and `NOTARY_KEYCHAIN_PROFILE` is set. Release mode signs with hardened runtime, creates one ZIP, and submits that same ZIP with `notarytool`; it does not rebuild the ZIP after approval. The delivered archive therefore relies on Apple's online notarization check on first launch rather than containing a stapled ticket for offline verification. If either signing or notarization credentials are unavailable, use the default QA mode and hand off only the `*-qa-only.zip` artifact.

```bash
SIGNING_MODE=release CODESIGN_IDENTITY="Developer ID Application: Example Team (TEAMID)" NOTARY_KEYCHAIN_PROFILE="paste-notary" ./scripts/build-macos.sh
```

## Runtime Shape

- `LSUIElement` is enabled in `Resources/Info.plist`, so launch does not open a Dock icon or a main window. The bundle still declares `PasteXAppIcon.icns` for Finder, application package, and Dock presentation if the activation policy changes.
- The app runs as a menu bar item using the clipboard icon.
- Left-click the menu bar item to toggle the bottom clipboard overlay.
- Right-click or Control-click the menu bar item to open a menu with `Show Clipboard History` and `Quit PasteX`.
- The menu also offers a manual update check; see the update and release instructions below.
- The default global shortcut is `Cmd+Option+V`. If registration fails because of a conflict, the app keeps running, the status item tooltip names the shortcut failure, and the right-click menu exposes `Show Clipboard History (menu fallback)` as the visible backup entry.

## Permissions

The app does not request Accessibility at launch. The permission path is first exercised when the user tries to paste from the overlay:

1. User selects an overlay item with Space, Return, or double-click.
2. `AccessibilityPermissionPresenter` calls `AXIsProcessTrustedWithOptions` with prompting enabled.
3. macOS shows the Accessibility consent prompt if the app is not trusted.
4. If the user grants permission, retrying the paste path can activate the captured target app and send `Cmd+V`.
5. If the user denies permission, the app keeps the selected item on the general pasteboard and returns the copied-only fallback.

Manual settings path: System Settings -> Privacy & Security -> Accessibility -> enable `PasteX`.

## QA Smoke Check

1. Open `dist/PasteX.app`; verify no main window or Dock icon appears, the app bundle shows the PasteX app icon in Finder, and a clipboard menu bar icon is visible.
2. Copy text, a URL, an image, and a file; verify the overlay shows recent items newest-first with type markers.
3. Toggle the overlay by menu bar click and by `Cmd+Option+V`.
4. Use Space, Return, and double-click to paste into TextEdit or another text input.
5. In a clean user profile, verify the first paste attempt triggers the Accessibility path, and denial falls back to copy-only with a visible overlay message instead of silently closing.
6. Right-click the menu bar icon, choose `Quit PasteX`, reopen the app, and verify the menu bar item and hotkey register again.
7. With another app already using `Cmd+Option+V`, launch PasteX and verify the status item tooltip/menu show the shortcut conflict and `Show Clipboard History (menu fallback)` still opens the overlay.

## 检测更新

右键或 Control-click 菜单栏图标，选择“检查更新…”（英文界面为 `Check for Updates…`）。独立窗口会显示检查进度和结果，并提供重新检查入口。应用读取 GitHub 最新稳定发布，比较版本号，并检查该版本是否包含适用的安装包。检查结果会说明已是最新版本、发现新版本或暂时无法检查；发现新版本后，点击“下载更新”可打开对应 GitHub 发布页。

当前提供 Apple Silicon 的 `PasteX-<版本>-macos-arm64-qa-only.zip`，更新检测不会自动下载、安装或替换应用。下载后退出 PasteX，用新版应用覆盖旧版，保留历史目录。QA 包采用 ad-hoc 签名，未经 Developer ID 签名或公证。

main 分支提交和 Pull Request 会先运行 macOS CI 全量测试。CI 和发布使用同一个 `scripts/test-macos-ci.sh` 入口，测试失败时保留非零退出状态并把关键错误写入 GitHub 检查注释，便于定位。已推送的失败版本标签保留；修复后递增版本并发布新标签。

发布前手动检查：当前版本无更新时能显示明确结果；网络不可用时显示失败且可以再次检查；有更高版本且带适用 ZIP 时能打开对应 GitHub 发布页；检查进行中不会发起重复请求。

## 通过 GitHub Actions 发布

工作流为 `.github/workflows/release-qa.yml`（Actions 中名为 `Release QA`）。发布前，将 `Resources/Info.plist` 的 `CFBundleShortVersionString` 与 `CFBundleVersion` 更新到相同版本，并写入 `docs/release/v<版本>.md`。工作流要求稳定版本标签为 `v主版本.次版本.补丁版本`，例如 `v1.1.4`。

提交代码后推送版本标签即可触发构建：

```bash
git tag v1.1.4
git push origin v1.1.4
```

也可以在 Actions → Release QA → Run workflow 中填写已存在的版本标签。工作流检出标签指向的提交，并检查标签、应用版本与发布说明是否一致。不要将已有标签移动到另一提交；修复代码后应使用新版本号和新标签。

工作流会依次完成：

1. 运行完整 `swift test --disable-sandbox`，涵盖更新检测和既有回归用例。
2. 使用 `SIGNING_MODE=qa` 构建 arm64 安装包，检查 ZIP 完整性、包内版本、架构和签名。
3. 生成 `PasteX-<版本>-macos-arm64-qa-only.zip` 及同名 `.zip.sha256` 校验文件，发布说明附上构建提交与 SHA-256。
4. 创建草稿发布，上传两个资产，重新下载并核验 SHA-256，成功后公开。失败的新发布保持草稿，不会被客户端当作可用更新。
5. 仅将版本号不低于所有已公开稳定版本的发布设为 latest，避免重跑旧标签让客户端回退到旧版本。不同标签的发布串行执行。

工作流使用仓库提供的 `GITHUB_TOKEN` 和 `contents: write` 权限，无需额外发布密钥。当前没有配置 Developer ID 证书或公证凭据，因此 Actions 发布的仍是明确标记 `qa-only` 的 QA 安装包。

同一标签失败后可重跑，工作流会复用草稿并重新上传资产。对已经公开的标签重跑会替换同名安装包和校验文件，但不会覆盖更高版本的 latest 标记；通常应通过新版本发布后续修复。

安装包下载到同一目录后，可在终端核验：

```bash
shasum -a 256 -c PasteX-1.1.4-macos-arm64-qa-only.zip.sha256
```
