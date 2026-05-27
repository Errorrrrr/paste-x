import PasteCore
import SwiftUI

public struct ClipboardKindBadge: View {
    private let kind: ClipboardKind

    public init(kind: ClipboardKind) {
        self.kind = kind
    }

    public var body: some View {
        Text(kind.badgeTitle)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(kind.foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(kind.backgroundColor)
            )
    }
}

private extension ClipboardKind {
    var badgeTitle: String {
        switch self {
        case .text:
            "TXT"
        case .url:
            "URL"
        case .image:
            "IMG"
        case .file:
            "FILE"
        case .unknown:
            "ITEM"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .text:
            Color(red: 0.09, green: 0.22, blue: 0.42)
        case .url:
            Color(red: 0.05, green: 0.31, blue: 0.24)
        case .image:
            Color(red: 0.36, green: 0.15, blue: 0.40)
        case .file:
            Color(red: 0.42, green: 0.24, blue: 0.04)
        case .unknown:
            Color(red: 0.22, green: 0.24, blue: 0.28)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .text:
            Color(red: 0.79, green: 0.88, blue: 1.00)
        case .url:
            Color(red: 0.72, green: 0.94, blue: 0.82)
        case .image:
            Color(red: 0.92, green: 0.82, blue: 0.97)
        case .file:
            Color(red: 1.00, green: 0.88, blue: 0.66)
        case .unknown:
            Color(red: 0.87, green: 0.89, blue: 0.92)
        }
    }
}
