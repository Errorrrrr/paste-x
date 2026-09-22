import AppKit
import PasteCore
import SwiftUI

struct LibraryToolbar: View {
    @ObservedObject var store: OverlaySelectionStore
    let language: AppLanguage
    let paste: (OverlayPasteRequest) -> Void
    private func t(_ zh: String, _ en: String) -> String { language == .simplifiedChinese ? zh : en }

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Button(t("全部历史", "All history")) { store.groupFilter = nil; store.pinnedOnly = false }
                Button(t("收藏", "Favorites")) { store.groupFilter = nil; store.pinnedOnly = true }
                ForEach(store.groups) { group in
                    Button(group.name) { store.groupFilter = group.id; store.pinnedOnly = false }
                }
                Divider()
                Button(t("新建分组…", "New group…")) { store.showsGroupCreation = true }
            } label: {
                Label(currentGroup, systemImage: store.pinnedOnly ? "pin.fill" : "folder")
            }
            .fixedSize()

            Menu {
                Button(t("所有类型", "All types")) { store.kindFilter = nil }
                ForEach(ClipboardKind.allCases, id: \.self) { kind in
                    Button(kind.rawValue) { store.kindFilter = kind }
                }
                Divider()
                Button(t("所有时间", "Any time")) { store.ageFilterDays = 0 }
                Button(t("最近一天", "Last day")) { store.ageFilterDays = 1 }
                Button(t("最近一周", "Last week")) { store.ageFilterDays = 7 }
                Button(t("最近一月", "Last month")) { store.ageFilterDays = 30 }
                Divider()
                Button(t("所有应用", "All apps")) { store.sourceFilter = "" }
                ForEach(appIDs, id: \.self) { id in
                    Button(store.items.first(where: { $0.sourceBundleID == id })?.sourceAppName ?? id) { store.sourceFilter = id }
                }
                Divider()
                Button(t("重置筛选", "Reset filters")) { store.resetFilters() }
            } label: {
                Label(filterTitle, systemImage: "line.3.horizontal.decrease.circle")
            }
            .fixedSize()

            Text("\(store.visibleItems.count)").foregroundStyle(.secondary).monospacedDigit()
            Spacer(minLength: 0)
            if !store.selectedIDs.isEmpty {
                Button(t("合并粘贴", "Paste combined")) {
                    if let request = store.mergedRequest() { paste(request) }
                }.disabled(store.mergedRequest() == nil || store.isPasting)
                Button(t("取消多选", "Deselect")) { store.selectedIDs.removeAll() }
            }
            Button { store.enqueueSelection() } label: {
                Label(t("加入队列", "Queue"), systemImage: "text.badge.plus")
            }.disabled(store.selectedItem == nil && store.selectedIDs.isEmpty)
            if !store.queueIDs.isEmpty {
                Menu {
                    Button(t("粘贴下一项 ⌘↵", "Paste next ⌘↵")) {
                        if let request = store.queueRequest() { paste(request) }
                    }.disabled(store.isPasting)
                    Button(t("反转顺序", "Reverse order")) { store.queueIDs.reverse() }
                    ForEach(Array(store.queueIDs.enumerated()), id: \.element) { index, id in
                        Button("\(index + 1). \(store.items.first(where: { $0.id == id })?.displayTitle ?? "") ×") {
                            store.queueIDs.removeAll { $0 == id }
                        }
                    }
                    Button(t("清空队列", "Clear queue")) { store.queueIDs.removeAll() }
                } label: { Label("\(store.queueIDs.count)", systemImage: "list.number") }
                .fixedSize()
            }
            Button {
                var settings = store.librarySettings
                settings.capturePaused.toggle()
                store.perform(.settings(settings))
            } label: {
                Image(systemName: store.librarySettings.capturePaused ? "play.fill" : "pause.fill")
            }.help(t("暂停或恢复记录", "Pause or resume capture"))
            Button { store.showsLibrarySettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .help(t("历史与隐私设置", "History and privacy"))
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 24)
        .frame(height: 30)
    }

    private var currentGroup: String {
        if let id = store.groupFilter { return store.groups.first { $0.id == id }?.name ?? t("全部历史", "All history") }
        return store.pinnedOnly ? t("收藏", "Favorites") : t("全部历史", "All history")
    }
    private var appIDs: [String] { Array(Set(store.items.compactMap(\.sourceBundleID))).sorted() }
    private var filterTitle: String {
        var parts: [String] = []
        if let kind = store.kindFilter { parts.append(kind.rawValue) }
        if store.ageFilterDays > 0 { parts.append("\(store.ageFilterDays)d") }
        if !store.sourceFilter.isEmpty { parts.append(store.items.first { $0.sourceBundleID == store.sourceFilter }?.sourceAppName ?? store.sourceFilter) }
        return parts.isEmpty ? t("筛选", "Filter") : parts.joined(separator: " · ")
    }
}

struct LibrarySettingsView: View {
    @ObservedObject var store: OverlaySelectionStore
    let language: AppLanguage
    let dismiss: () -> Void
    @State private var settings: ClipboardLibrarySettings
    @State private var exclusions: String
    @State private var confirmsClear = false
    @State private var renameID: UUID?
    @State private var renameText = ""
    private func t(_ zh: String, _ en: String) -> String { language == .simplifiedChinese ? zh : en }

    init(store: OverlaySelectionStore, language: AppLanguage, dismiss: @escaping () -> Void) {
        self.store = store; self.language = language; self.dismiss = dismiss
        _settings = State(initialValue: store.librarySettings)
        _exclusions = State(initialValue: store.librarySettings.excludedBundleIDs.joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("历史与隐私", "History & privacy")).font(.title2.bold())
            Form {
                TextField(t("最多条数（0 为不限）", "History limit (0 = unlimited)"), value: $settings.historyLimit, format: .number)
                TextField(t("保留天数（0 为永久）", "Keep days (0 = forever)"), value: $settings.retentionDays, format: .number)
                TextField(t("历史容量 MB", "History capacity MB"), value: $settings.storageLimitMB, format: .number)
                Toggle(t("忽略保密和临时内容", "Ignore confidential and transient content"), isOn: $settings.ignoreConfidential)
                Toggle(t("暂停记录", "Pause capture"), isOn: $settings.capturePaused)
                Toggle(t("本地识别图片文字（OCR）", "Recognize image text locally (OCR)"), isOn: $settings.recognizeImages)
                Text(t("忽略以下应用（每行一个 Bundle ID）", "Ignore applications (one bundle ID per line)")).font(.caption)
                TextEditor(text: $exclusions).font(.system(.caption, design: .monospaced)).frame(height: 75)
                Text(t("收藏和分组内的内容不会自动清理。文件仅保存引用；历史保存在本机，未另行加密。更改保留规则会立即清理过期内容。",
                       "Favorites and grouped items do not expire. Files are references. History stays on this Mac, without additional encryption. Retention changes immediately remove expired items."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !store.groups.isEmpty {
                Text(t("分组", "Groups")).font(.headline)
                ScrollView {
                    ForEach(store.groups) { group in
                        HStack {
                            Text(group.name)
                            Spacer()
                            Button(t("重命名", "Rename")) { renameID = group.id; renameText = group.name }
                            Button(t("移除分组", "Remove group")) { store.perform(.deleteGroup(group.id)) }
                        }
                    }
                }.frame(height: 80)
                Text(t("移除分组会保留内容。", "Removing a group keeps its items.")).font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.storageError {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button(t("清空未收藏历史…", "Clear unpinned history…"), role: .destructive) { confirmsClear = true }
                Spacer()
                Button(t("取消", "Cancel")) { dismiss() }
                Button(t("保存", "Save")) {
                    settings.excludedBundleIDs = exclusions.components(separatedBy: .newlines)
                    store.perform(.settings(settings))
                    if store.storageError == nil { dismiss() }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 540)
        .alert(t("清空未收藏历史？", "Clear unpinned history?"), isPresented: $confirmsClear) {
            Button(t("清空", "Clear"), role: .destructive) { store.perform(.clearHistory) }
            Button(t("取消", "Cancel"), role: .cancel) {}
        } message: { Text(t("收藏和分组内容会保留，其他历史将从磁盘移除。", "Favorites and grouped items remain; other history is removed from disk.")) }
        .alert(t("重命名分组", "Rename group"), isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField(t("名称", "Name"), text: $renameText)
            Button(t("保存", "Save")) { if let id = renameID { store.perform(.renameGroup(id, renameText)) }; renameID = nil }
            Button(t("取消", "Cancel"), role: .cancel) { renameID = nil }
        }
    }
}

struct ClipboardDetailView: View {
    let item: ClipboardItem
    let language: AppLanguage
    let save: (ClipboardItem) -> Void
    let dismiss: () -> Void
    @State private var label: String
    @State private var text: String
    @State private var editing = false
    @State private var error: String?
    private func t(_ zh: String, _ en: String) -> String { language == .simplifiedChinese ? zh : en }

    init(item: ClipboardItem, language: AppLanguage, dismiss: @escaping () -> Void, save: @escaping (ClipboardItem) -> Void) {
        self.item = item; self.language = language; self.save = save; self.dismiss = dismiss
        _label = State(initialValue: item.label); _text = State(initialValue: item.textContent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(t("内容详情", "Item details")).font(.title2.bold())
                Spacer()
                Text(item.sourceAppName ?? "").foregroundStyle(.secondary)
                Text(item.createdAt, style: .date).foregroundStyle(.secondary)
            }
            TextField(t("名称（可搜索）", "Name (searchable)"), text: $label).textFieldStyle(.roundedBorder)
            if item.kind == .image, let image = ClipboardImagePreview.make(from: item)?.image, !editing {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 200)
            }
            if item.kind == .file {
                ScrollView {
                    ForEach(item.fileURLs, id: \.self) { url in
                        HStack {
                            FileQuickLookThumbnail(url: url).frame(width: 70, height: 70)
                            VStack(alignment: .leading) {
                                Text(url.lastPathComponent)
                                Text(url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer()
                            if FileManager.default.fileExists(atPath: url.path) {
                                Button(t("在 Finder 显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            } else { Text(t("文件已不存在", "File missing")).foregroundStyle(.red) }
                        }
                    }
                }.frame(height: 260)
            } else if editing {
                TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(height: 260)
                Text(t("保存编辑会将此项转换为纯文本。", "Saving edits converts this item to plain text.")).font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    if let rich = richText {
                        Text(rich).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(text.isEmpty ? item.summary : text).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(minHeight: 80, maxHeight: 260)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                if item.kind != .file {
                    Button(editing ? t("取消编辑", "Cancel edit") : t("编辑文本", "Edit text")) {
                        editing.toggle(); if !editing { text = item.textContent }
                    }
                    Menu(t("文本处理", "Transform")) {
                        ForEach(ClipboardTextTransform.allCases, id: \.self) { transform in
                            Button(transformTitle(transform)) {
                                do { text = try transform.apply(to: text); editing = true; error = nil }
                                catch { self.error = t("无法转换：", "Cannot transform: ") + error.localizedDescription }
                            }
                        }
                    }.fixedSize()
                }
                Spacer()
                Button(t("关闭", "Close")) { dismiss() }
                Button(t("保存", "Save")) {
                    var updated = editing ? item.replacingText(text) : item
                    updated.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(updated)
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 640)
    }
    private var richText: AttributedString? {
        for payload in item.payloads {
            let rich: NSAttributedString?
            switch payload.typeIdentifier {
            case "public.rtf": rich = NSAttributedString(rtf: payload.data, documentAttributes: nil)
            case "com.apple.flat-rtfd": rich = NSAttributedString(rtfd: payload.data, documentAttributes: nil)
            default: rich = nil
            }
            if let rich { return AttributedString(rich) }
        }
        return nil
    }
    private func transformTitle(_ transform: ClipboardTextTransform) -> String {
        switch transform {
        case .formatJSON: return t("格式化 JSON", "Format JSON")
        case .encodeURL: return t("URL 编码", "URL encode")
        case .decodeURL: return t("URL 解码", "URL decode")
        case .trimWhitespace: return t("去除首尾空白", "Trim whitespace")
        }
    }
}


struct ClipboardGroupCreationView: View {
    @ObservedObject var store: OverlaySelectionStore
    let language: AppLanguage
    let dismiss: () -> Void
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(language == .english ? "New group" : "新建分组").font(.title2.bold())
            TextField(language == .english ? "Group name" : "分组名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(create)
            if let error = store.storageError { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer()
                Button(language == .english ? "Cancel" : "取消", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(language == .english ? "Create" : "创建", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear { nameFocused = true }
    }

    private func create() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.perform(.createGroup(name))
        if store.storageError == nil { dismiss() }
    }
}
