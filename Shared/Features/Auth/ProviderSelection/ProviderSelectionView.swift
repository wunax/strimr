import SwiftUI

struct ProviderSelectionView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("provider.selection.title")
                    .font(.largeTitle.bold())
                Text("provider.selection.subtitle")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 20) {
                providerButton(
                    title: "provider.plex",
                    systemImage: "play.tv.fill",
                    provider: .plex,
                )
                providerButton(
                    title: "provider.jellyfin",
                    systemImage: "triangle.fill",
                    provider: .jellyfin,
                )
            }
        }
        .padding(32)
        .frame(maxWidth: 720, maxHeight: .infinity)
    }

    private func providerButton(
        title: LocalizedStringKey,
        systemImage: String,
        provider: MediaProvider,
    ) -> some View {
        Button {
            Task { await sessionManager.selectProvider(provider) }
        } label: {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 42, weight: .semibold))
                Text(title)
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        }
        .buttonStyle(.borderedProminent)
    }
}
