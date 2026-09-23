import AppKit
import Foundation
import Testing
import PasteCore
@testable import PasteMacSystem

private func clip(_ text: String, at date: Date = Date(), pinned: Bool = false) -> ClipboardItem {
    let payloads = [ClipboardPayload(typeIdentifier: "public.utf8-plain-text", data: Data(text.utf8))]
    return ClipboardItem(kind: .text, summary: String(text.prefix(120)), createdAt: date,
                         signature: ClipboardSignature.make(kind: .text, payloads: payloads),
                         payloads: payloads, isPinned: pinned)
}

@Test func diskLibraryRestoresPayloadsMetadataGroupsAndSettings() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ClipboardHistoryStore(directory: folder)
    store.apply(.createGroup("工作"))
    let group = try #require(store.groups.first)
    var item = clip("完整内容" + String(repeating: "长", count: 200))
    item.label = "接口"; item.groupID = group.id; item.isPinned = true
    item.sourceAppName = "Editor"; item.sourceBundleID = "test.editor"
    store.insert(item)
    var settings = store.settings
    settings.historyLimit = 200; settings.excludedBundleIDs = ["test.secret"]
    store.apply(.settings(settings))
    let restored = ClipboardHistoryStore(directory: folder)
    #expect(restored.storageError == nil)
    #expect(restored.items == [item])
    #expect(restored.groups == [group])
    #expect(restored.settings == settings)
}

@Test func libraryExpiresOnStartupAndRemovesUnreferencedFilesButKeepsPins() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let initial = Date()
    let store = ClipboardHistoryStore(directory: folder, now: { initial })
    let ordinary = clip("ordinary", at: initial)
    let pinned = clip("pinned", at: initial, pinned: true)
    store.insert(ordinary); store.insert(pinned)
    let restored = ClipboardHistoryStore(directory: folder, now: { initial.addingTimeInterval(31 * 86400) })
    #expect(restored.items == [pinned])
    let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(!files.contains { $0.hasPrefix(ordinary.id.uuidString) })
    #expect(files.count == 2)
}

@Test func historyLimitDoesNotEvictPinnedOrGroupedContent() throws {
    let store = ClipboardHistoryStore(capacity: 1)
    store.apply(.createGroup("Keep"))
    var grouped = clip("group")
    grouped.groupID = try #require(store.groups.first?.id)
    store.insert(grouped); store.insert(clip("pinned", pinned: true))
    store.insert(clip("old")); store.insert(clip("new"))
    #expect(Set(store.items.map(\.summary)) == ["new", "pinned", "group"])
    store.apply(.clearHistory)
    #expect(Set(store.items.map(\.summary)) == ["pinned", "group"])
}

@Test func corruptManifestIsPreservedAndBlocksWrites() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("manifest.json")
    let original = Data("broken original".utf8)
    try original.write(to: url)
    let store = ClipboardHistoryStore(directory: folder)
    store.insert(clip("do not overwrite"))
    #expect(store.storageError != nil)
    #expect(try Data(contentsOf: url) == original)
    #expect(store.items.isEmpty)
}

@Test func olderSettingsWithoutNewFieldsPreserveHistoryAndExistingPreferences() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ClipboardHistoryStore(directory: folder)
    let item = clip("keep history", pinned: true)
    store.insert(item)
    let url = folder.appendingPathComponent("manifest.json")
    var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    manifest["settings"] = ["historyLimit": 87, "retentionDays": 0, "capturePaused": true,
                            "excludedBundleIDs": ["test.private"]]
    try JSONSerialization.data(withJSONObject: manifest).write(to: url)
    let restored = ClipboardHistoryStore(directory: folder)
    #expect(restored.storageError == nil)
    #expect(restored.items == [item])
    #expect(restored.settings.historyLimit == 87)
    #expect(restored.settings.retentionDays == 0)
    #expect(restored.settings.capturePaused)
    #expect(restored.settings.excludedBundleIDs == ["test.private"])
    #expect(restored.settings.storageLimitMB == ClipboardLibrarySettings().storageLimitMB)
    restored.insert(clip("new content"))
    #expect(ClipboardHistoryStore(directory: folder).items.count == 2)
}

@Test func legacyLibraryMigratesWithoutRemovingOriginalRecords() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var item = clip("legacy history", pinned: true)
    item.sourceBundleID = "example.source"
    let record = folder.appendingPathComponent("\(item.id.uuidString).json")
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
    object["sourceBundleIdentifier"] = object.removeValue(forKey: "sourceBundleID")
    try JSONSerialization.data(withJSONObject: object).write(to: record)
    let manifestURL = folder.appendingPathComponent("manifest.json")
    let legacyManifest: [String: Any] = [
        "version": 1, "itemIDs": [item.id.uuidString], "pinboards": [],
        "preferences": ["historyLimit": 87, "retentionDays": 0,
                        "excludedBundleIdentifiers": ["example.private"], "isPaused": true,
                        "pasteAsPlainText": true, "batchSeparator": "\n"]
    ]
    let originalManifest = try JSONSerialization.data(withJSONObject: legacyManifest)
    try originalManifest.write(to: manifestURL)

    let migrated = ClipboardHistoryStore(directory: folder)
    #expect(migrated.storageError == nil)
    #expect(migrated.items.count == 1)
    #expect(migrated.items.first?.sourceBundleID == "example.source")
    #expect(migrated.settings.historyLimit == 87)
    #expect(migrated.settings.retentionDays == 0)
    #expect(migrated.settings.excludedBundleIDs == ["example.private"])
    #expect(migrated.settings.capturePaused)
    #expect(try Data(contentsOf: folder.appendingPathComponent("manifest.legacy-v1.json")) == originalManifest)
    #expect(FileManager.default.fileExists(atPath: record.path))

    migrated.insert(clip("new history"))
    let restored = ClipboardHistoryStore(directory: folder)
    #expect(restored.storageError == nil)
    #expect(restored.items.count == 2)
    #expect(restored.items.last?.sourceBundleID == "example.source")
    #expect(FileManager.default.fileExists(atPath: record.path))
}

@Test func legacyPinboardsStayReadOnlyUntilSupported() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let manifestURL = folder.appendingPathComponent("manifest.json")
    let original = try JSONSerialization.data(withJSONObject: [
        "version": 1, "itemIDs": [], "pinboards": [["id": UUID().uuidString]],
        "preferences": ["historyLimit": 100, "retentionDays": 30,
                        "excludedBundleIdentifiers": [], "isPaused": false,
                        "pasteAsPlainText": false, "batchSeparator": "\n"]
    ] as [String: Any])
    try original.write(to: manifestURL)
    let store = ClipboardHistoryStore(directory: folder)
    store.insert(clip("do not overwrite"))
    #expect(store.storageError?.contains("旧版收藏板") == true)
    #expect(try Data(contentsOf: manifestURL) == original)
    #expect(store.items.isEmpty)
}

@Test func invalidSettingsRemainReadOnlyWithActionableDiagnostic() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    _ = ClipboardHistoryStore(directory: folder)
    let url = folder.appendingPathComponent("manifest.json")
    var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var settings = try #require(manifest["settings"] as? [String: Any])
    settings["historyLimit"] = "invalid-private-value"
    manifest["settings"] = settings
    let original = try JSONSerialization.data(withJSONObject: manifest)
    try original.write(to: url)
    let restored = ClipboardHistoryStore(directory: folder)
    restored.insert(clip("do not overwrite"))
    #expect(restored.storageError?.contains("settings.historyLimit") == true)
    #expect(restored.storageError?.contains("invalid-private-value") == false)
    #expect(try Data(contentsOf: url) == original)
}

@Test func missingLaterRecordDoesNotExposePartialLibraryOrOverwriteManifest() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ClipboardHistoryStore(directory: folder)
    let older = clip("missing record", pinned: true)
    store.insert(older)
    store.insert(clip("readable record", pinned: true))
    store.apply(.createGroup("Keep"))
    let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    let missingFile = try #require(files.first { $0.hasPrefix(older.id.uuidString) })
    try FileManager.default.removeItem(at: folder.appendingPathComponent(missingFile))
    let manifest = folder.appendingPathComponent("manifest.json")
    let original = try Data(contentsOf: manifest)
    let restored = ClipboardHistoryStore(directory: folder)
    #expect(restored.items.isEmpty)
    #expect(restored.groups.isEmpty)
    #expect(restored.storageError?.contains(missingFile) == true)
    restored.insert(clip("do not overwrite"))
    #expect(try Data(contentsOf: manifest) == original)
}

@Test func nullExistingPrivacySettingIsNotResetToDefault() throws {
    let json = Data(#"{"capturePaused":null}"#.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ClipboardLibrarySettings.self, from: json)
    }
}

@Test func failedDiskWriteRollsBackMemoryAndKeepsSavedLibrary() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ClipboardHistoryStore(directory: folder)
    let original = clip("saved")
    store.insert(original)
    let manifest = folder.appendingPathComponent("manifest.json")
    try FileManager.default.removeItem(at: manifest)
    try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
    store.insert(clip("unsaved"))
    #expect(store.storageError != nil)
    #expect(store.items == [original])
}

@Test func duplicateRetainsIdentityAndOrganization() {
    let store = ClipboardHistoryStore()
    var original = clip("same", pinned: true); original.label = "常用"
    store.insert(original); store.insert(clip("other")); store.insert(clip("same"))
    #expect(store.items.count == 2)
    #expect(store.items.first?.id == original.id)
    #expect(store.items.first?.label == "常用")
    #expect(store.items.first?.isPinned == true)
}

@Test func legacyItemDecodingDefaultsToOnePasteboardObject() throws {
    let item = clip("legacy")
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
    for key in ["label", "isPinned", "groupID", "sourceAppName", "sourceBundleID", "extractedText"] { object.removeValue(forKey: key) }
    var payloads = try #require(object["payloads"] as? [[String: Any]])
    payloads[0].removeValue(forKey: "itemIndex"); object["payloads"] = payloads
    let decoded = try JSONDecoder().decode(ClipboardItem.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded.payloads[0].itemIndex == 0)
    #expect(decoded.label.isEmpty && !decoded.isPinned)
    #expect(decoded.textContent == "legacy")
}

@Test func privacyFilterSkipsExcludedConfidentialAndPausedCopies() {
    let source = PrivacySource()
    let store = ClipboardHistoryStore()
    let monitor = ClipboardMonitor(source: source, classifier: ClipboardClassifier(), historyStore: store)
    var settings = ClipboardLibrarySettings()
    settings.excludedBundleIDs = ["secret.app"]
    monitor.settingsProvider = { settings }
    source.bundleID = "secret.app"; source.copy("secret"); monitor.poll()
    source.bundleID = "allowed.app"
    source.copy("password", marker: "org.nspasteboard.ConcealedType"); monitor.poll()
    source.copy("temporary", marker: "org.nspasteboard.TransientType"); monitor.poll()
    monitor.isPaused = true
    source.copy("paused")
    monitor.isPaused = false
    monitor.poll()
    #expect(store.items.isEmpty)
    source.copy("safe"); monitor.poll()
    #expect(store.items.map(\.summary) == ["safe"])
    #expect(store.items.first?.sourceBundleID == "allowed.app")
}

@Test func selfWriteSuppressionStillWorksWithMultipleItems() {
    let source = PrivacySource()
    let store = ClipboardHistoryStore()
    let monitor = ClipboardMonitor(source: source, classifier: ClipboardClassifier(), historyStore: store)
    source.payloads = (0..<2).map { ClipboardPayload(typeIdentifier: "public.file-url", data: Data("file:///tmp/\($0).txt".utf8), itemIndex: $0) }
    monitor.markSelfWrite(signature: ClipboardSignature.make(kind: .file, payloads: source.payloads))
    source.count += 1; monitor.poll()
    #expect(store.items.isEmpty)
}

@MainActor
@Test func multipleFileObjectsRoundTripThroughSystemPasteboard() throws {
    let input = NSPasteboard.withUniqueName(), output = NSPasteboard.withUniqueName()
    defer { input.releaseGlobally(); output.releaseGlobally() }
    let urls = [URL(fileURLWithPath: "/tmp/one.txt"), URL(fileURLWithPath: "/tmp/two.txt")]
    #expect(input.writeObjects(urls.map { $0 as NSURL }))
    let source = SystemClipboardPayloadSource(pasteboard: input)
    let payloads = source.currentPayloads()
    #expect(Set(payloads.map(\.itemIndex)) == [0, 1])
    let item = try #require(ClipboardClassifier().makeItem(from: payloads, createdAt: Date()))
    #expect(SystemPasteCoordinatorServices(pasteboard: output).writeToPasteboard(item))
    #expect(output.pasteboardItems?.count == 2)
    let roundTrip = try #require(output.readObjects(forClasses: [NSURL.self]) as? [URL])
    #expect(roundTrip == urls)
}

private final class PrivacySource: ClipboardPayloadSource {
    var count = 0
    var payloads: [ClipboardPayload] = []
    var bundleID = "test.app"
    func copy(_ text: String, marker: String? = nil) {
        count += 1
        payloads = [ClipboardPayload(typeIdentifier: "public.utf8-plain-text", data: Data(text.utf8))]
        if let marker { payloads.append(ClipboardPayload(typeIdentifier: marker, data: Data())) }
    }
    func currentChangeCount() -> Int { count }
    func currentPayloads() -> [ClipboardPayload] { payloads }
    func sourceApplication() -> (name: String?, bundleID: String?) { ("Test App", bundleID) }
}

@MainActor
@Test func localOCRRecognizesSyntheticImageText() async throws {
    let image = NSImage(size: NSSize(width: 640, height: 160))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 640, height: 160).fill()
    ("PASTEX LOCAL SEARCH 2026" as NSString).draw(at: NSPoint(x: 20, y: 65),
        withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black])
    image.unlockFocus()
    let data = try #require(image.tiffRepresentation)
    let text = try await ClipboardTextRecognizer.recognize(data)
    #expect(text.uppercased().contains("LOCAL SEARCH"))
    #expect(text.contains("2026"))
}

@Test func groupingParticipatesInSignatureAndTextEditingPreservesMetadata() {
    let first = ClipboardPayload(typeIdentifier: "public.file-url", data: Data("file:///tmp/a".utf8))
    let second = ClipboardPayload(typeIdentifier: "public.file-url", data: Data("file:///tmp/b".utf8), itemIndex: 1)
    let collapsed = ClipboardPayload(typeIdentifier: second.typeIdentifier, data: second.data)
    #expect(ClipboardSignature.make(kind: .file, payloads: [first, second]) != ClipboardSignature.make(kind: .file, payloads: [first, collapsed]))
    var item = clip("original", pinned: true)
    item.groupID = UUID(); item.label = "keep"
    let edited = item.replacingText("updated\nbody")
    #expect(edited.id == item.id && edited.groupID == item.groupID && edited.isPinned)
    #expect(edited.textContent == "updated\nbody")
    #expect(edited.label == "keep")
    #expect(edited.signature != item.signature)
}

@Test func removalOfGroupKeepsItemsPinnedAndOrphanRecordsAreReclaimed() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ClipboardHistoryStore(directory: folder)
    store.apply(.createGroup("Keep"))
    let group = try #require(store.groups.first)
    var item = clip("grouped"); item.groupID = group.id
    store.insert(item)
    store.apply(.deleteGroup(group.id))
    #expect(store.items.first?.isPinned == true)
    store.apply(.clearHistory)
    #expect(store.items.count == 1)
    let orphan = folder.appendingPathComponent("\(UUID().uuidString)-\(UUID().uuidString).json")
    try Data("orphaned record".utf8).write(to: orphan)
    let other = folder.appendingPathComponent("notes.json")
    try Data("unrelated".utf8).write(to: other)
    let reopened = ClipboardHistoryStore(directory: folder)
    #expect(reopened.items.count == 1)
    #expect(!FileManager.default.fileExists(atPath: orphan.path))
    #expect(FileManager.default.fileExists(atPath: other.path))
}
