import SwiftUI

@MainActor
struct IntegrationsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SeerrStore.self) private var seerrStore

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            SettingsScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SettingsLink(title: "integrations.seerr.title") {
                        SeerrView(
                            viewModel: SeerrViewModel(
                                store: seerrStore,
                                sessionManager: sessionManager,
                                sessionService: SeerrSessionService(),
                            ),
                        )
                    } label: {
                        integrationCard(
                            title: "integrations.seerr.title",
                            subtitle: seerrStatusText,
                            systemImage: "film",
                            isConnected: seerrStore.isLoggedIn,
                        )
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: LayoutMetrics.cardCornerRadius))
                    .settingsFocus("seerr", isDefault: true)

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
        }
    }

    private var seerrStatusText: String {
        if let baseURL = seerrStore.baseURLString {
            return baseURL
        }

        return String(localized: "integrations.seerr.setup.description")
    }

    private func integrationCard(
        title: LocalizedStringKey,
        subtitle: String,
        systemImage: String,
        isConnected: Bool,
    ) -> some View {
        HStack(spacing: 24) {
            ZStack {
                // Hierarchical styles: the card is the label of a bordered button, which turns white when focused.
                RoundedRectangle(cornerRadius: MediaArtworkMetrics.compactCornerRadius, style: .continuous)
                    .fill(.secondary.opacity(0.2))

                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.sectionTitle)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .font(.facts)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)
            }

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
