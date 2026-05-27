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
        ZStack {
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
        }
        .frame(minWidth: 420, idealHeight: 96, maxHeight: 96)
        .padding(10)
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

    private func requestPaste(trigger: OverlayPasteTrigger) {
        guard let request = store.makePasteRequest(trigger: trigger) else {
            return
        }

        onPasteRequest(request)
    }
}
