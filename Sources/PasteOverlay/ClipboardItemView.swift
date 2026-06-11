import AppKit
import PasteCore
import SwiftUI

public struct ClipboardItemView: View {
    private let item: ClipboardItem
    private let displayIndex: Int
    private let language: AppLanguage
    private let isSelected: Bool
    private let onSelect: () -> Void
    private let onPaste: () -> Void

    public init(
        item: ClipboardItem,
        displayIndex: Int,
        language: AppLanguage = .english,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onPaste: @escaping () -> Void
    ) {
        self.item = item
        self.displayIndex = displayIndex
        self.language = language
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onPaste = onPaste
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            previewBody
            footer
        }
        .frame(width: 248, height: 244, alignment: .topLeading)
        .background(itemBackground)
        .overlay(selectionStroke)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            ClipboardItemMouseEventBridge(onSelect: onSelect, onPaste: onPaste)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.kind.rawValue), \(item.summary)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            item.kind.headerColor

            VStack(alignment: .leading, spacing: 2) {
                Text(item.kind.displayTitle(language: language))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(relativeTimeText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.trailing, 72)

            ClipboardKindCornerMark(kind: item.kind)
                .frame(width: 58, height: 52)
        }
        .frame(height: 52)
    }

    @ViewBuilder
    private var previewBody: some View {
        switch item.kind {
        case .url:
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 0)

                Image(systemName: "safari")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                Text(urlTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(urlSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

        case .image:
            let preview = ClipboardImagePreview.make(from: item)

            ZStack(alignment: .bottomTrailing) {
                CheckerboardView()

                if let preview {
                    Image(nsImage: preview.image)
                        .resizable()
                        .interpolation(.medium)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(12)
                        .accessibilityLabel(imagePreviewAccessibilityLabel)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 48, weight: .regular))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(imagePreviewAccessibilityLabel)
                }

                Text(imageDimensionText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.52))
                    )
                    .padding(.trailing, 18)
                    .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .file:
            let preview = ClipboardImagePreview.makeFromFilePayloads(item.payloads)

            VStack(spacing: 12) {
                Spacer(minLength: 0)

                if let preview {
                    ZStack {
                        CheckerboardView()

                        Image(nsImage: preview.image)
                            .resizable()
                            .interpolation(.medium)
                            .antialiased(true)
                            .scaledToFit()
                            .padding(10)
                    }
                    .frame(width: 128, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
                    )
                    .accessibilityLabel(imagePreviewAccessibilityLabel)
                } else {
                    FileThumbnailView()
                        .frame(width: 82, height: 110)
                }

                Spacer(minLength: 0)

                Text(fileDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .text, .unknown:
            Text(item.summary)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
        }
    }

    private var footer: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(footerSummary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("\(displayIndex)")
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 28)
    }

    private var itemBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
    }

    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                isSelected ? Color(nsColor: .controlAccentColor) : Color(nsColor: .separatorColor).opacity(0.12),
                lineWidth: isSelected ? 4 : 1
            )
    }

    private var relativeTimeText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(item.createdAt)))
        let minute = 60
        let hour = minute * 60
        let day = hour * 24

        if seconds < minute {
            return language == .english ? "Just now" : "刚刚"
        } else if seconds < hour {
            return language == .english ? "\(max(1, seconds / minute))m ago" : "\(max(1, seconds / minute))分钟前"
        } else if seconds < day {
            return language == .english ? "\(max(1, seconds / hour))h ago" : "\(max(1, seconds / hour))小时前"
        } else {
            return language == .english ? "\(max(1, seconds / day))d ago" : "\(max(1, seconds / day))天前"
        }
    }

    private var footerSummary: String {
        switch item.kind {
        case .text, .unknown:
            return language == .english ? "\(item.summary.count) characters" : "\(item.summary.count) 个字符"
        case .url:
            return urlHost
        case .image:
            return imageDimensionText
        case .file:
            return fileDisplayName
        }
    }

    private var urlTitle: String {
        guard let host = URL(string: item.summary)?.host(percentEncoded: false), !host.isEmpty else {
            return item.summary
        }

        return host
    }

    private var urlSubtitle: String {
        if let url = URL(string: item.summary), let host = url.host(percentEncoded: false) {
            return item.summary.replacingOccurrences(of: "https://\(host)", with: host)
        }

        return item.summary
    }

    private var urlHost: String {
        URL(string: item.summary)?.host(percentEncoded: false) ?? (language == .english ? "Link" : "链接")
    }

    private var fileDisplayName: String {
        if let url = URL(string: item.summary), url.isFileURL {
            return url.lastPathComponent
        }

        return item.summary.split(separator: "/").last.map(String.init) ?? item.summary
    }

    private var imageDimensionText: String {
        let pattern = #/(\d+)\s*[x×]\s*(\d+)/#
        if let match = item.summary.firstMatch(of: pattern) {
            return "\(match.1) × \(match.2)"
        }

        return language == .english ? "Image" : "图片"
    }

    private var imagePreviewAccessibilityLabel: String {
        language == .english ? "Image preview" : "图片预览"
    }
}

extension ClipboardItemView: @preconcurrency Equatable {
    public static func == (lhs: ClipboardItemView, rhs: ClipboardItemView) -> Bool {
        lhs.item == rhs.item
            && lhs.displayIndex == rhs.displayIndex
            && lhs.language == rhs.language
            && lhs.isSelected == rhs.isSelected
    }
}

private struct ClipboardItemMouseEventBridge: NSViewRepresentable {
    let onSelect: () -> Void
    let onPaste: () -> Void

    func makeNSView(context: Context) -> ClipboardItemMouseEventView {
        let view = ClipboardItemMouseEventView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: ClipboardItemMouseEventView, context: Context) {
        nsView.onSelect = onSelect
        nsView.onPaste = onPaste
    }
}

final class ClipboardItemMouseEventView: NSView {
    var onSelect: () -> Void = {}
    var onPaste: () -> Void = {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        handleMouseDown(event)
    }

    func handleMouseDown(_ event: NSEvent) {
        if event.clickCount >= 2 {
            onPaste()
        } else {
            onSelect()
        }
    }
}

extension NSView {
    func firstClipboardItemMouseEventView(containingWindowPoint windowPoint: NSPoint) -> ClipboardItemMouseEventView? {
        guard !isHidden else {
            return nil
        }

        let localPoint = convert(windowPoint, from: nil)
        guard bounds.contains(localPoint) else {
            return nil
        }

        if let mouseEventView = self as? ClipboardItemMouseEventView {
            return mouseEventView
        }

        for subview in subviews.reversed() {
            if let mouseEventView = subview.firstClipboardItemMouseEventView(containingWindowPoint: windowPoint) {
                return mouseEventView
            }
        }

        return nil
    }
}

private struct ClipboardKindCornerMark: View {
    let kind: ClipboardKind

    var body: some View {
        ZStack {
            switch kind {
            case .url:
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.16), radius: 7, x: 0, y: 2)
                    .padding(6)

                Image(systemName: "safari.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(kind.headerColor)
            case .file:
                PatternTileView()
            case .image:
                PatternTileView()
            case .text, .unknown:
                PatternTileView()
            }
        }
        .clipShape(TopRightCardCorner())
    }
}

private struct PatternTileView: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.82, green: 0.90, blue: 0.94)

                Path { path in
                    let step: CGFloat = 13
                    var x: CGFloat = 0
                    while x <= proxy.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                        x += step
                    }

                    var y: CGFloat = 0
                    while y <= proxy.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        y += step
                    }
                }
                .stroke(Color.white.opacity(0.42), lineWidth: 1)

                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(Color.white.opacity(0.52), lineWidth: 1.2)
                        .frame(width: CGFloat(22 + index * 18), height: CGFloat(22 + index * 18))
                }
            }
        }
    }
}

private struct CheckerboardView: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let size: CGFloat = 12
                let columns = Int(proxy.size.width / size) + 1
                let rows = Int(proxy.size.height / size) + 1

                for row in 0..<rows {
                    for column in 0..<columns where (row + column).isMultiple(of: 2) {
                        path.addRect(CGRect(x: CGFloat(column) * size, y: CGFloat(row) * size, width: size, height: size))
                    }
                }
            }
            .fill(Color(nsColor: .separatorColor).opacity(0.12))
            .background(Color.white.opacity(0.84))
        }
    }
}

private struct FileThumbnailView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.16), radius: 7, x: 0, y: 3)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<10, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(index.isMultiple(of: 3) ? Color(nsColor: .labelColor).opacity(0.34) : Color(nsColor: .separatorColor).opacity(0.42))
                            .frame(width: index.isMultiple(of: 4) ? 42 : 58, height: 2)
                    }
                }
                .padding(10)
            }
    }
}

private struct TopRightCardCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: 12, height: 12),
            style: .continuous
        )
        return path
    }
}

private extension ClipboardKind {
    func displayTitle(language: AppLanguage) -> String {
        switch self {
        case .text:
            return language == .english ? "Text" : "文本"
        case .url:
            return language == .english ? "Link" : "链接"
        case .image:
            return language == .english ? "Image" : "图片"
        case .file:
            return language == .english ? "1 File" : "1 个文件"
        case .unknown:
            return language == .english ? "Item" : "项目"
        }
    }

    var headerColor: Color {
        switch self {
        case .text:
            return Color(red: 0.52, green: 0.52, blue: 0.50)
        case .url:
            return Color(red: 0.23, green: 0.49, blue: 0.91)
        case .image:
            return Color(red: 0.50, green: 0.50, blue: 0.48)
        case .file:
            return Color(red: 0.50, green: 0.50, blue: 0.48)
        case .unknown:
            return Color(red: 0.48, green: 0.48, blue: 0.46)
        }
    }
}
