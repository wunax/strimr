import SwiftUI

@MainActor
struct WatchTogetherView: View {
    @Environment(WatchTogetherViewModel.self) private var viewModel
    @State private var isShowingLeavePrompt = false

    var body: some View {
        ZStack(alignment: .top) {
            Color("Background").ignoresSafeArea()
            backgroundDecor
            content()
        }
        .navigationTitle("watchTogether.title")
        .alert("watchTogether.leave.title", isPresented: $isShowingLeavePrompt) {
            Button("watchTogether.leave.justMe") {
                viewModel.leaveSession(endForAll: false)
            }

            if viewModel.isHost {
                Button("watchTogether.leave.endAll", role: .destructive) {
                    viewModel.leaveSession(endForAll: true)
                }
            }

            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("watchTogether.leave.message")
        }
        .overlay(alignment: .top) {
            ToastOverlay(toasts: viewModel.toasts)
        }
    }

    @ViewBuilder
    private func content() -> some View {
        if viewModel.isInSession {
            lobbyView()
        } else {
            entryView()
        }
    }

    private func entryView() -> some View {
        let joinCodeBinding = Binding(
            get: { viewModel.joinCode },
            set: { viewModel.joinCode = $0 },
        )

        return GeometryReader { proxy in
            let usesTwoColumns = proxy.size.width >= 1280

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    connectionStatusBadge

                    if usesTwoColumns {
                        HStack(alignment: .top, spacing: 20) {
                            createSessionPanel
                            joinSessionPanel(joinCodeBinding: joinCodeBinding)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            createSessionPanel
                            joinSessionPanel(joinCodeBinding: joinCodeBinding)
                        }
                    }

                    if let error = viewModel.errorMessage {
                        errorCard(error)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func lobbyView() -> some View {
        GeometryReader { proxy in
            let usesTwoColumns = proxy.size.width >= 1480
            let sideColumnWidth = min(max(proxy.size.width * 0.33, 360), 500)

            ScrollView {
                if usesTwoColumns {
                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 20) {
                            sessionInfoPanel
                            selectedMediaSection
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 20) {
                            participantsSection
                            actionsSection
                        }
                        .frame(width: sideColumnWidth, alignment: .topLeading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        sessionInfoPanel
                        participantsSection
                        selectedMediaSection
                        actionsSection
                    }
                }
            }
            .padding(48)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var backgroundDecor: some View {
        ZStack {
            Circle()
                .fill(Color.brandPrimary.opacity(0.15))
                .frame(width: 520, height: 520)
                .blur(radius: 120)
                .offset(x: -360, y: -320)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 380, height: 380)
                .blur(radius: 140)
                .offset(x: 460, y: -260)
        }
        .allowsHitTesting(false)
    }

    private var createSessionPanel: some View {
        WatchTogetherPanel(
            titleKey: "watchTogether.create.title",
            systemImage: "sparkles.tv",
        ) {
            Button("watchTogether.create.action") {
                viewModel.createSession()
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func joinSessionPanel(joinCodeBinding: Binding<String>) -> some View {
        WatchTogetherPanel(
            titleKey: "watchTogether.join.title",
            systemImage: "rectangle.and.text.magnifyingglass",
        ) {
            VStack(alignment: .leading, spacing: 14) {
                TextField("watchTogether.join.placeholder", text: joinCodeBinding)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Button("watchTogether.join.action") {
                    viewModel.joinSession()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sessionInfoPanel: some View {
        WatchTogetherPanel(
            titleKey: "watchTogether.session.code",
            systemImage: "link",
        ) {
            VStack(alignment: .leading, spacing: 16) {
                connectionStatusBadge

                Text(viewModel.code)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .tracking(3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var participantsSection: some View {
        WatchTogetherPanel(
            titleKey: "watchTogether.participants.title",
            systemImage: "person.3.fill",
            trailing: {
                Text("\(readyParticipantsCount)/\(viewModel.participants.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            },
        ) {
            if viewModel.participants.isEmpty {
                Text("common.empty.nothingToShow")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.participants) { participant in
                        WatchTogetherParticipantRow(
                            participant: participant,
                            hasSelectedMedia: viewModel.selectedMedia != nil,
                        )
                    }
                }
            }
        }
    }

    private var selectedMediaSection: some View {
        WatchTogetherPanel(
            titleKey: "watchTogether.selectedMedia.title",
            systemImage: "film.fill",
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let selectedMedia = viewModel.selectedMedia {
                    WatchTogetherSelectedMediaCard(media: selectedMedia)
                } else {
                    Text("watchTogether.selectedMedia.empty")
                        .foregroundStyle(.secondary)
                }

                if viewModel.isHost {
                    NavigationLink("watchTogether.selectMedia") {
                        WatchTogetherSearchView { media in
                            viewModel.setSelectedMedia(media)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.secondary)
                    .controlSize(.regular)
                }
            }
        }
    }

    private var actionsSection: some View {
        WatchTogetherPanel(
            titleKey: "watchTogether.actions.title",
            systemImage: "play.circle.fill",
        ) {
            let isReady = viewModel.readyMap[viewModel.currentParticipantId ?? ""] == true

            VStack(alignment: .leading, spacing: 12) {
                Button(isReady ? "watchTogether.ready.on" : "watchTogether.ready.off") {
                    viewModel.toggleReady()
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
                .controlSize(.regular)

                if viewModel.isHost {
                    Button("watchTogether.startPlayback") {
                        viewModel.startPlayback()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .controlSize(.regular)
                    .disabled(!viewModel.canStartPlayback)
                }

                Button("watchTogether.leave.title", role: .destructive) {
                    isShowingLeavePrompt = true
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var connectionStatusBadge: some View {
        let presentation = connectionPresentation

        return HStack(spacing: 10) {
            Image(systemName: presentation.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(presentation.tint)

            Text(presentation.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08)),
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectionPresentation: (title: LocalizedStringKey, icon: String, tint: Color) {
        switch viewModel.connectionState {
        case .connecting:
            ("watchTogether.status.connecting", "arrow.triangle.2.circlepath.circle.fill", .orange)
        case .reconnecting:
            ("watchTogether.status.reconnecting", "arrow.triangle.2.circlepath", .orange)
        case .connected:
            ("watchTogether.status.connected", "checkmark.circle.fill", .green)
        case .disconnected:
            ("watchTogether.status.disconnected", "wifi.slash", .red)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(0.30)),
        )
    }

    private var readyParticipantsCount: Int {
        viewModel.participants.filter(\.isReady).count
    }
}

private struct WatchTogetherPanel<Content: View, Trailing: View>: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    private let trailing: Trailing
    private let content: Content

    init(
        titleKey: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content,
    ) where Trailing == EmptyView {
        self.titleKey = titleKey
        self.systemImage = systemImage
        trailing = EmptyView()
        self.content = content()
    }

    init(
        titleKey: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content,
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(titleKey, systemImage: systemImage)
                    .font(.headline.weight(.semibold))
                Spacer()
                trailing
            }

            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06)),
        )
        .focusSection()
    }
}

private struct WatchTogetherParticipantRow: View {
    let participant: WatchTogetherParticipant
    let hasSelectedMedia: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: participant.isReady ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(participant.isReady ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(participant.displayName)
                        .font(.subheadline.weight(.semibold))

                    if participant.isHost {
                        Text("watchTogether.host.badge")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.brandPrimary.opacity(0.2)),
                            )
                    }
                }

                if hasSelectedMedia, !participant.hasMediaAccess {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.callout)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04)),
        )
    }
}

private struct WatchTogetherSelectedMediaCard: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    let media: WatchTogetherSelectedMedia
    @State private var imageURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 130, height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(media.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)

                Text(typeLabel(for: media.type))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05)),
        )
        .task(id: media.ratingKey) {
            await loadImage()
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "film")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.gray.opacity(0.6)),
            )
    }

    private func typeLabel(for type: PlexItemType) -> String {
        switch type {
        case .movie:
            String(localized: "search.badge.movie")
        case .show:
            String(localized: "search.badge.show")
        case .season:
            String(localized: "search.badge.season")
        case .episode:
            String(localized: "search.badge.episode")
        case .collection:
            String(localized: "search.badge.collection")
        case .playlist:
            String(localized: "search.badge.playlist")
        case .unknown:
            String(localized: "search.badge.unknown")
        }
    }

    private func loadImage() async {
        imageURL = nil

        guard let path = media.thumbPath else {
            imageURL = nil
            return
        }

        do {
            let repository = try ImageRepository(context: plexApiContext)
            imageURL = repository.transcodeImageURL(path: path)
        } catch {
            imageURL = nil
        }
    }
}

private struct WatchTogetherSearchView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.dismiss) private var dismiss
    let onSelect: (MediaDisplayItem) -> Void

    var body: some View {
        SearchTVView(viewModel: SearchViewModel(context: plexApiContext)) { media in
            onSelect(media)
            dismiss()
        }
    }
}
