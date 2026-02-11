import SwiftUI
import UIKit

@MainActor
struct WatchTogetherView: View {
    @Environment(WatchTogetherViewModel.self) private var viewModel
    @State private var isShowingLeavePrompt = false

    var body: some View {
        ZStack(alignment: .top) {
            content()
        }
        .navigationTitle("watchTogether.title")
        .toolbar {
            if viewModel.isInSession {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("watchTogether.leave.title") {
                        isShowingLeavePrompt = true
                    }
                }
            }
        }
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

        return List {
            Section {
                statusView
            }

            Section("watchTogether.create.title") {
                Button("watchTogether.create.action") {
                    viewModel.createSession()
                }
            }

            Section("watchTogether.join.title") {
                TextField("watchTogether.join.placeholder", text: joinCodeBinding)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Button("watchTogether.join.action") {
                    viewModel.joinSession()
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func lobbyView() -> some View {
        VStack(spacing: 16) {
            List {
                Section {
                    statusView
                    sessionInfo
                }

                Section("watchTogether.participants.title") {
                    participantsList
                }

                Section("watchTogether.selectedMedia.title") {
                    selectedMediaSection
                }

                Section {
                    actionsSection
                }
            }
            .listStyle(.insetGrouped)

            if viewModel.isHost {
                startPlaybackButton
            }
        }
        .padding(.bottom, 12)
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

            HStack(spacing: 8) {
                Text(viewModel.code)
                    .font(.title2.weight(.bold))

                Button {
                    UIPasteboard.general.string = viewModel.code
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .accessibilityLabel(Text("watchTogether.session.copy"))
            }
        }
    }

    private var participantsList: some View {
        ForEach(viewModel.participants) { participant in
            WatchTogetherParticipantRow(
                participant: participant,
                hasSelectedMedia: viewModel.selectedMedia != nil,
            )
        }
    }

    private var selectedMediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        Toggle(
            "watchTogether.ready.toggle",
            isOn: Binding(
                get: { viewModel.readyMap[viewModel.currentParticipantId ?? ""] ?? false },
                set: { _ in viewModel.toggleReady() },
            ),
        )
    }

    private var startPlaybackButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("watchTogether.startPlayback") {
                viewModel.startPlayback()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(!viewModel.canStartPlayback)

            if viewModel.requiresMoreParticipantsToStartPlayback {
                Text("watchTogether.error.minimumParticipants")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .frame(width: 90, height: 135)
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
        SearchView(viewModel: SearchViewModel(context: plexApiContext)) { media in
            onSelect(media)
            dismiss()
        }
    }
}
