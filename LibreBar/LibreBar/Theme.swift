import SwiftUI

enum Theme {
    static let cardCornerRadius: CGFloat = 10
    static let sectionSpacing: CGFloat = 12
    static let popoverWidth: CGFloat = 340
    static let popoverPadding: CGFloat = 14
    static let popoverHeight: CGFloat = 540
    static let heroValueSize: CGFloat = 34
    static let sectionLabelTracking: CGFloat = 0.7
}

struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(Theme.sectionLabelTracking)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 2)
    }
}

struct StatusPill: View {
    let systemImage: String?
    let text: String
    var tint: Color = .secondary

    init(_ text: String, systemImage: String? = nil, tint: Color = .secondary) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(tint)
        .padding(.leading, systemImage == nil ? 9 : 8)
        .padding(.trailing, 9)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.14), in: Capsule())
    }
}
