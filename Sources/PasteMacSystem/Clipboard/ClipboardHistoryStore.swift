import Foundation
import PasteCore

/// Mutated on the app's main thread. Passing no directory creates an isolated in-memory library.
public final class ClipboardHistoryStore: ClipboardHistoryProviding {
    public private(set) var items: [ClipboardItem] = []
    public private(set) var groups: [ClipboardGroup] = []
    public private(set) var settings = ClipboardLibrarySettings()
    public private(set) var storageError: String?
    public var onChange: (() -> Void)?
    private let directory: URL?
    private var loadFailed = false
    private var itemFiles: [UUID: String] = [:]
    private let now: () -> Date

    private struct Manifest: Codable {
        var version = 1
        var order: [UUID]
        var files: [UUID: String]
        var groups: [ClipboardGroup]
        var settings: ClipboardLibrarySettings
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PasteX/Library", isDirectory: true)
    }

    public init(capacity: Int = 1000, directory: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
        settings.historyLimit = max(0, capacity)
        if directory == nil { settings.retentionDays = 0 }
        load()
        if !loadFailed { let loaded = items; prune(); persist(previousItems: loaded) }
    }

    public func insert(_ incoming: ClipboardItem) {
        transact {
            var item = incoming
            if let previous = items.first(where: { $0.signature == item.signature && $0.id != item.id }) {
                item = ClipboardItem(id: previous.id, kind: item.kind, summary: item.summary, createdAt: item.createdAt,
                                     signature: item.signature, payloads: item.payloads, label: previous.label,
                                     isPinned: previous.isPinned, groupID: previous.groupID,
                                     sourceAppName: item.sourceAppName, sourceBundleID: item.sourceBundleID,
                                     extractedText: item.extractedText.isEmpty ? previous.extractedText : item.extractedText)
            }
            items.removeAll { $0.signature == item.signature || $0.id == item.id }
            items.insert(item, at: 0)
            prune()
        }
    }

    public func clear() { transact { items.removeAll() } }

    public func apply(_ action: ClipboardLibraryAction) {
        transact {
            switch action {
            case let .update(item):
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
                prune()
            case let .delete(ids): items.removeAll { ids.contains($0.id) }
            case .clearHistory: items.removeAll { !$0.isPinned && $0.groupID == nil }
            case let .createGroup(name):
                let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { groups.append(ClipboardGroup(name: name)) }
            case let .renameGroup(id, name):
                let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, let index = groups.firstIndex(where: { $0.id == id }) { groups[index].name = name }
            case let .deleteGroup(id):
                groups.removeAll { $0.id == id }
                for index in items.indices where items[index].groupID == id {
                    items[index].groupID = nil
                    items[index].isPinned = true
                }
            case let .move(id, target):
                if id != target, let source = items.firstIndex(where: { $0.id == id }), items.contains(where: { $0.id == target }) {
                    let item = items.remove(at: source)
                    if let destination = items.firstIndex(where: { $0.id == target }) { items.insert(item, at: destination) }
                }
            case var .settings(value):
                value.historyLimit = max(0, value.historyLimit)
                value.retentionDays = max(0, min(36500, value.retentionDays))
                value.storageLimitMB = max(50, min(100000, value.storageLimitMB))
                value.excludedBundleIDs = value.excludedBundleIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                settings = value
                prune()
            }
        }
    }

    public func expireItems() { transact { prune() } }

    private func prune() {
        let cutoff = now().addingTimeInterval(-Double(settings.retentionDays) * 86400)
        var count = 0
        var bytes = items.filter { $0.isPinned || $0.groupID != nil }.reduce(0) { $0 + $1.byteCount }
        items = items.filter { item in
            if item.isPinned || item.groupID != nil { return true }
            if settings.retentionDays > 0 && item.createdAt < cutoff { return false }
            if settings.historyLimit > 0 && count >= settings.historyLimit { return false }
            if bytes + item.byteCount > settings.storageLimitMB * 1024 * 1024 { return false }
            count += 1
            bytes += item.byteCount
            return true
        }
    }

    private func transact(_ mutation: () -> Void) {
        guard !loadFailed else { onChange?(); return }
        let previous = items, previousGroups = groups, previousSettings = settings
        mutation()
        if !persist(previousItems: previous) {
            items = previous; groups = previousGroups; settings = previousSettings
        }
        onChange?()
    }

    private func load() {
        guard let directory else { return }
        let url = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Never silently replace an unrecognized pre-existing library.
            if let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path), !files.isEmpty {
                storageError = "已有历史库格式无法识别，原文件已保留。 / Unrecognized existing library; files preserved."
                loadFailed = true
            }
            return
        }
        var readingFile = "manifest.json"
        do {
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
            guard manifest.version == 1, Set(manifest.order).count == manifest.order.count else { throw CocoaError(.fileReadCorruptFile) }
            var loadedItems: [ClipboardItem] = []
            for id in manifest.order {
                guard let file = manifest.files[id], file == URL(fileURLWithPath: file).lastPathComponent,
                      file.hasSuffix(".json") else { throw CocoaError(.fileReadCorruptFile) }
                readingFile = file
                let item = try JSONDecoder().decode(ClipboardItem.self, from: Data(contentsOf: directory.appendingPathComponent(file)))
                guard item.id == id else { throw CocoaError(.fileReadCorruptFile) }
                loadedItems.append(item)
            }
            // Publish only a complete library; a broken record must not expose a
            // partially loaded history with settings/groups from a failed read.
            items = loadedItems
            groups = manifest.groups; settings = manifest.settings; itemFiles = manifest.files
        } catch {
            loadFailed = true
            storageError = "历史库读取失败，已保留原文件并停止写入。 / Library unreadable; original files preserved.\n\(readingFile): \(Self.readFailureReason(error))"
        }
    }

    private static func readFailureReason(_ error: Error) -> String {
        func field(_ path: [any CodingKey]) -> String {
            path.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case let DecodingError.keyNotFound(key, context):
            return "缺少字段 / Missing field: \(field(context.codingPath + [key]))"
        case let DecodingError.typeMismatch(_, context):
            return "字段类型不兼容 / Incompatible field type: \(field(context.codingPath))"
        case let DecodingError.valueNotFound(_, context):
            return "字段值为空 / Null field: \(field(context.codingPath))"
        case let DecodingError.dataCorrupted(context):
            return "数据格式无效 / Invalid data: \(field(context.codingPath))"
        default:
            let nsError = error as NSError
            return "\(nsError.localizedDescription) [\(nsError.domain):\(nsError.code)]"
        }
    }

    private static func isRecordFile(_ name: String) -> Bool {
        guard name.count == 78, name.hasSuffix(".json") else { return false }
        let stem = String(name.dropLast(5))
        return UUID(uuidString: String(stem.prefix(36))) != nil
            && stem[stem.index(stem.startIndex, offsetBy: 36)] == "-"
            && UUID(uuidString: String(stem.suffix(36))) != nil
    }

    @discardableResult
    private func persist(previousItems: [ClipboardItem]) -> Bool {
        guard let directory else { return true }
        let fm = FileManager.default
        var newFiles = itemFiles
        var written: [URL] = []
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let previous = Dictionary(uniqueKeysWithValues: previousItems.map { ($0.id, $0) })
            for item in items where previous[item.id] != item || newFiles[item.id] == nil {
                let name = "\(item.id.uuidString)-\(UUID().uuidString).json"
                let url = directory.appendingPathComponent(name)
                try JSONEncoder().encode(item).write(to: url, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                newFiles[item.id] = name; written.append(url)
            }
            let ids = Set(items.map(\.id))
            newFiles = newFiles.filter { ids.contains($0.key) }
            let manifest = Manifest(order: items.map(\.id), files: newFiles, groups: groups, settings: settings)
            try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
            let obsolete = Set(itemFiles.values).subtracting(newFiles.values)
            itemFiles = newFiles
            for name in obsolete { try? fm.removeItem(at: directory.appendingPathComponent(name)) }
            if let files = try? fm.contentsOfDirectory(atPath: directory.path) {
                let active = Set(newFiles.values)
                for name in files where !active.contains(name) && Self.isRecordFile(name) {
                    try? fm.removeItem(at: directory.appendingPathComponent(name))
                }
            }
            storageError = nil
            return true
        } catch {
            for url in written { try? fm.removeItem(at: url) }
            storageError = "无法保存历史库，操作未保存。 / Could not save library. \(error.localizedDescription)"
            return false
        }
    }
}
