import SwiftUI

@MainActor
struct IntegrationsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SeerrStore.self) private var seerrStore

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("settings.integrations.title")
                        .font(.largeTitle.bold())

                    NavigationLink {
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
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(48)
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.12))

                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .font(.callout)
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
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
