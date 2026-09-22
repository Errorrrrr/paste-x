import AppKit
import Foundation
import PasteCore
import PasteMacSystem

extension ClipboardAssistantDependencyContainer {
    /// Isolated visual QA: synthetic items, no clipboard monitoring, no real paste or persistent user settings.
    public static func demo() -> ClipboardAssistantDependencyContainer {
        let container = ClipboardAssistantDependencyContainer(
            pasteCoordinator: DemoPasteCoordinator(), permissionPresenter: nil, settingsPresenter: nil,
            shortcutStore: nil, appSettingsStore: nil, launchAtLoginManager: nil,
            quitHandler: { NSApp.terminate(nil) }
        )
        let classifier = ClipboardClassifier()
        let examples = [
            "欢迎使用 PasteX\n收藏常用内容，按应用与时间筛选。⌘1–9 快速粘贴，⇧↵ 纯文本粘贴。",
            String(repeating: "这是一段用于验证全文搜索的长文本。", count: 15) + "\n深处的关键词：星河",
            "{\"project\":\"PasteX\",\"features\":[\"本地保存\",\"隐私\",\"OCR\"]}",
            "https://example.com/docs?language=zh",
        ]
        for (index, text) in examples.enumerated() {
            if var item = classifier.makeItem(from: [.init(typeIdentifier: "public.utf8-plain-text", data: Data(text.utf8))], createdAt: Date().addingTimeInterval(Double(-index * 60))) {
                item.sourceAppName = index == 2 ? "Xcode" : "Safari"
                item.sourceBundleID = index == 2 ? "com.apple.dt.Xcode" : "com.apple.Safari"
                container.historyStore.insert(item)
            }
        }
        let demoFolder = FileManager.default.temporaryDirectory.appendingPathComponent("PasteXDemo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: demoFolder, withIntermediateDirectories: true)
        let report = demoFolder.appendingPathComponent("PasteX-QA.pdf")
        let documentView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        documentView.string = "PasteX Preview Report\\n\\nLocal clipboard library\\nFile thumbnail verification\\n2026"
        documentView.font = .systemFont(ofSize: 24)
        documentView.textColor = .black
        documentView.backgroundColor = .white
        if (try? documentView.dataWithPDF(inside: documentView.bounds).write(to: report)) != nil,
           let item = classifier.makeItem(from: [.init(typeIdentifier: "public.file-url", data: Data(report.absoluteString.utf8))], createdAt: Date()) {
            container.historyStore.insert(item)
        }
        let rich = NSAttributedString(string: "富文本预览\n保留颜色、粗体与排版", attributes: [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.systemBlue])
        if let data = try? rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]),
           let item = classifier.makeItem(from: [.init(typeIdentifier: "public.rtf", data: data)], createdAt: Date()) { container.historyStore.insert(item) }

        let image = NSImage(size: NSSize(width: 640, height: 220))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 640, height: 220).fill()
        ("PasteX OCR 2026\nLocal clipboard search" as NSString).draw(at: NSPoint(x: 25, y: 70), withAttributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black])
        image.unlockFocus()
        if let data = image.tiffRepresentation,
           let item = classifier.makeItem(from: [.init(typeIdentifier: "public.tiff", data: data)], createdAt: Date()) { container.historyStore.insert(item) }

        container.historyStore.apply(.createGroup("工作"))
        if var item = container.historyStore.items.last {
            item.isPinned = true; item.label = "快速上手"; item.groupID = container.historyStore.groups.first?.id
            container.historyStore.apply(.update(item))
        }
        return container
    }
}

private final class DemoPasteCoordinator: PasteCoordinating {
    func paste(_ item: ClipboardItem, to target: PasteTarget?) async -> PasteResult { .copiedOnly(reason: .targetUnavailable) }
}
