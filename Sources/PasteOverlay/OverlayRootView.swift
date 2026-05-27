import PasteCore
import SwiftUI

public struct OverlayRootView: View {
    @ObservedObject private var store: OverlaySelectionStore
    private let onPasteRequest: (OverlayPasteRequest) -> Void

    public init(
        store: OverlaySelectionStore,
        onPasteRequest: @escaping (OverlayPasteRequest) -> Void
    ) {
        self.store = store
        self.onPasteRequest = onPasteRequest
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
                )

            if store.items.isEmpty {
                emptyState
            } else {
                itemStrip
            }

            if let feedbackMessage = store.feedbackMessage {
                feedbackBanner(feedbackMessage)
                    .padding(.trailing, 18)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 420, idealHeight: 96, maxHeight: 96)
        .padding(10)
        .animation(.easeOut(duration: 0.14), value: store.feedbackMessage)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            Text("No clipboard items")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.items) { item in
                        ClipboardItemView(
                            item: item,
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
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
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
}
