import PasteCore
import SwiftUI

public enum OverlayMenuAction: String, Codable, Equatable, Sendable {
    case settings
    case close
    case quit
}

public struct OverlayRootView: View {
    @ObservedObject private var store: OverlaySelectionStore
    private let language: AppLanguage
    private let onPasteRequest: (OverlayPasteRequest) -> Void
    private let onMenuAction: (OverlayMenuAction) -> Void
    @FocusState private var isSearchFieldFocused: Bool

    public init(
        store: OverlaySelectionStore,
        language: AppLanguage = .english,
        onPasteRequest: @escaping (OverlayPasteRequest) -> Void,
        onMenuAction: @escaping (OverlayMenuAction) -> Void = { _ in }
    ) {
        self.store = store
        self.language = language
        self.onPasteRequest = onPasteRequest
        self.onMenuAction = onMenuAction
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            overlayBackground

            VStack(spacing: 8) {
                toolbar

                if store.visibleItems.isEmpty {
                    emptyState
                } else {
                    itemStrip
                }
            }

            if let feedbackMessage = store.feedbackMessage {
                feedbackBanner(feedbackMessage)
                    .padding(.trailing, 28)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 316, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.14), value: store.feedbackMessage)
        .onChange(of: store.isSearching) { _, isSearching in
            isSearchFieldFocused = isSearching
        }
    }

    private var overlayBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.68),
                    Color(nsColor: .systemTeal).opacity(0.12),
                    Color(nsColor: .systemBlue).opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .ignoresSafeArea()
    }

    private var toolbar: some View {
        ZStack {
            HStack(spacing: 16) {
                searchControl

                Label(strings.clipboardTitle, systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(nsColor: .controlColor).opacity(0.78))
                    )
            }
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            HStack {
                Spacer()

                menuControl
                    .padding(.trailing, 28)
            }
        }
        .frame(height: 56)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var searchControl: some View {
        if store.isSearching || !store.searchQuery.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                TextField(
                    strings.searchPlaceholder,
                    text: Binding(
                        get: { store.searchQuery },
                        set: { store.updateSearchQuery($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .focused($isSearchFieldFocused)
                .frame(width: 220)
                .onSubmit {
                    requestPaste(trigger: .returnKey)
                }

                if !store.searchQuery.isEmpty {
                    Button {
                        store.deactivateSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .accessibilityLabel(strings.clearSearchAccessibility)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.36), lineWidth: 1)
            )
            .onAppear {
                isSearchFieldFocused = true
            }
        } else {
            Button {
                store.activateSearch()
                isSearchFieldFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(strings.searchAccessibility)
        }
    }

    private var menuControl: some View {
        Menu {
            Button {
                onMenuAction(.settings)
            } label: {
                Label(strings.settings, systemImage: "gearshape")
            }

            Button {
                onMenuAction(.close)
            } label: {
                Label(strings.closeWindow, systemImage: "xmark")
            }

            Button(role: .destructive) {
                onMenuAction(.quit)
            } label: {
                Label(strings.quit, systemImage: "power")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 34, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(strings.moreAccessibility)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: store.items.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)

            Text(store.items.isEmpty ? strings.noClipboardItems : strings.noMatchingItems)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 34)
    }

    private var itemStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { index, item in
                        ClipboardItemView(
                            item: item,
                            displayIndex: index + 1,
                            language: language,
                            isSelected: item.id == store.selectedItemID,
                            onSelect: {
                                store.select(id: item.id)
                            },
                            onPaste: {
                                store.select(id: item.id)
                                requestPaste(trigger: .doubleClick)
                            }
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 28)
            }
            .onChange(of: store.selectedItemID) { _, newValue in
                guard let newValue else {
                    return
                }

                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func feedbackBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(Color(nsColor: .controlAccentColor))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 360, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
        .accessibilityLabel(message)
    }

    private func requestPaste(trigger: OverlayPasteTrigger) {
        guard let request = store.makePasteRequest(trigger: trigger) else {
            return
        }

        onPasteRequest(request)
    }

    private var strings: OverlayStrings {
        OverlayStrings(language: language)
    }
}

private struct OverlayStrings {
    let language: AppLanguage

    var clipboardTitle: String {
        switch language {
        case .english:
            return "Clipboard"
        case .simplifiedChinese:
            return "剪贴板"
        }
    }

    var searchPlaceholder: String {
        switch language {
        case .english:
            return "Search clipboard"
        case .simplifiedChinese:
            return "搜索剪贴板"
        }
    }

    var searchAccessibility: String {
        switch language {
        case .english:
            return "Search clipboard"
        case .simplifiedChinese:
            return "搜索剪贴板"
        }
    }

    var clearSearchAccessibility: String {
        switch language {
        case .english:
            return "Clear search"
        case .simplifiedChinese:
            return "清除搜索"
        }
    }

    var settings: String {
        switch language {
        case .english:
            return "Settings"
        case .simplifiedChinese:
            return "设置"
        }
    }

    var closeWindow: String {
        switch language {
        case .english:
            return "Close Window"
        case .simplifiedChinese:
            return "关闭窗口"
        }
    }

    var quit: String {
        switch language {
        case .english:
            return "Quit PasteX"
        case .simplifiedChinese:
            return "退出 PasteX"
        }
    }

    var moreAccessibility: String {
        switch language {
        case .english:
            return "More"
        case .simplifiedChinese:
            return "更多"
        }
    }

    var noClipboardItems: String {
        switch language {
        case .english:
            return "No clipboard items"
        case .simplifiedChinese:
            return "没有剪贴板内容"
        }
    }

    var noMatchingItems: String {
        switch language {
        case .english:
            return "No matching clipboard items"
        case .simplifiedChinese:
            return "没有匹配的剪贴板内容"
        }
    }
}
