import PasteCore
import SwiftUI

public struct ClipboardItemView: View {
    private let item: ClipboardItem
    private let isSelected: Bool
    private let onSelect: () -> Void
    private let onPaste: () -> Void

    public init(
        item: ClipboardItem,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onPaste: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onPaste = onPaste
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ClipboardKindBadge(kind: item.kind)

                Spacer(minLength: 0)

                Text(item.createdAt, style: .time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }

            Text(item.summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 224, height: 72, alignment: .topLeading)
        .background(itemBackground)
        .overlay(selectionStroke)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onPaste)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.kind.rawValue), \(item.summary)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var itemBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
    }

    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(
                isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5),
                lineWidth: isSelected ? 2 : 1
            )
    }
}
