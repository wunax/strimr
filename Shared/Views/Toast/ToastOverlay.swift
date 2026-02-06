import SwiftUI

struct ToastMessage: Identifiable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String?

    init(id: UUID = UUID(), title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

struct ToastOverlay: View {
    let toasts: [ToastMessage]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toasts) { toast in
                ToastView(message: toast)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut, value: toasts)
        .allowsHitTesting(false)
    }
}

private struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.title)
                .font(.headline)
                .foregroundStyle(.white)

            if let subtitle = message.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.60)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1),
        )
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 6)
    }
}
