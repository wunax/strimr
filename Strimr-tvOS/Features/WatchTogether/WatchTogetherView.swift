import SwiftUI

@MainActor
struct WatchTogetherView: View {
    @Environment(WatchTogetherViewModel.self) private var viewModel
    @State private var isShowingLeavePrompt = false

    var body: some View {
        ZStack(alignment: .top) {
            Color("Background").ignoresSafeArea()
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

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statusView

                VStack(alignment: .leading, spacing: 12) {
                    Text("watchTogether.create.title")
                        .font(.title3.weight(.semibold))
                    Button("watchTogether.create.action") {
                        viewModel.createSession()
                    }
                    .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("watchTogether.join.title")
                        .font(.title3.weight(.semibold))

                    TextField("watchTogether.join.placeholder", text: joinCodeBinding)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    Button("watchTogether.join.action") {
                        viewModel.joinSession()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(48)
        }
    }

    private func lobbyView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statusView
                sessionInfo
                participantsSection
                selectedMediaSection
                actionsSection
            }
            .padding(48)
        }
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch viewModel.connectionState {
            case .connecting:
                Text("watchTogether.status.connecting")
                    .foregroundStyle(.secondary)
            case .reconnecting:
                Text("watchTogether.status.reconnecting")
                    .foregroundStyle(.secondary)
            case .connected:
                Text("watchTogether.status.connected")
                    .foregroundStyle(.secondary)
            case .disconnected:
                Text("watchTogether.status.disconnected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sessionInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("watchTogether.session.code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(viewModel.code)
                .font(.title2.weight(.bold))
        }
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("watchTogether.participants.title")
                .font(.title3.weight(.semibold))

            ForEach(viewModel.participants) { participant in
                WatchTogetherParticipantRow(
                    participant: participant,
                    hasSelectedMedia: viewModel.selectedMedia != nil,
                )
            }
        }
    }

    private var selectedMediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("watchTogether.selectedMedia.title")
                .font(.title3.weight(.semibold))

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
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("watchTogether.actions.title")
                .font(.title3.weight(.semibold))

            let isReady = viewModel.readyMap[viewModel.currentParticipantId ?? ""] == true

            HStack(spacing: 16) {
                Button(isReady ? "watchTogether.ready.on" : "watchTogether.ready.off") {
                    viewModel.toggleReady()
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)

                if viewModel.isHost {
                    Button("watchTogether.startPlayback") {
                        viewModel.startPlayback()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .disabled(!viewModel.canStartPlayback)
                }
            }

            Button("watchTogether.leave.title", role: .destructive) {
                isShowingLeavePrompt = true
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct WatchTogetherParticipantRow: View {
    let participant: WatchTogetherParticipant
    let hasSelectedMedia: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(participant.displayName)
                .font(.headline)

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

            Spacer()

            if hasSelectedMedia, !participant.hasMediaAccess {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }

            Image(systemName: participant.isReady ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(participant.isReady ? .green : .secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct WatchTogetherSelectedMediaCard: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    let media: WatchTogetherSelectedMedia
    @State private var imageURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
            .frame(width: 120, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(media.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(typeLabel(for: media.type))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gray.opacity(0.12)),
        )
        .task {
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
