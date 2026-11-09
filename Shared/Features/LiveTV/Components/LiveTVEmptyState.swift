import SwiftUI

struct LiveTVEmptyState: View {
    let key: LocalizedStringKey
    let systemImage: String
    let message: String?

    init(_ key: LocalizedStringKey, systemImage: String, message: String? = nil) {
        self.key = key
        self.systemImage = systemImage
        self.message = message
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.textTertiary)
            Text(key)
                .font(.bodyText)
                .multilineTextAlignment(.center)
                .foregroundStyle(.textSecondary)
            if let message {
                Text(message)
                    .font(.facts)
                    .foregroundStyle(.textTertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
