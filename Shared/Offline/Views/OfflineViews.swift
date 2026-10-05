import SwiftUI

struct DownloadStatusBadge: View {
    @Environment(DownloadManager.self) private var downloadManager
    let media: MediaDisplayItem

    var body: some View {
        if let state = downloadManager.badgeState(for: media) {
            content(for: state)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.black.opacity(0.65), in: Capsule(style: .continuous))
                .padding(8)
                // Keeps the badge above the resume progress bar drawn along the bottom edge.
                .padding(.bottom, 10)
                .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func content(for state: DownloadBadgeState) -> some View {
        switch state {
        case .queued:
            Image(systemName: "clock")
                .accessibilityLabel("downloads.status.queued")
        case let .downloading(progress):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .tint(.white)
                .accessibilityLabel("offline.badge.downloading")
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .accessibilityLabel("offline.badge.downloaded")
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("downloads.status.failed")
        case let .partial(downloaded, total):
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle.fill")
                if let total, total > 0 {
                    Text("offline.badge.partial \(downloaded) \(total)")
                } else {
                    Text("\(downloaded)")
                }
            }
        }
    }
}

/// Partial download indicator for series and seasons ("3/10 episodes downloaded").
struct DownloadedEpisodesLabel: View {
    @Environment(DownloadManager.self) private var downloadManager
    let media: MediaItem

    var body: some View {
        let downloaded = downloadManager.completedEpisodes(inContainer: media).count
        if downloaded > 0 {
            Label {
                if let total = media.leafCount, total > 0 {
                    Text("offline.detail.downloadedEpisodes \(downloaded) \(total)")
                } else {
                    Text("offline.detail.downloadedEpisodesCount \(downloaded)")
                }
            } icon: {
                Image(systemName: "arrow.down.circle.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

struct OfflineBanner: View {
    @Environment(OfflineCoordinator.self) private var offlineCoordinator

    var body: some View {
        if let banner = offlineCoordinator.banner {
            Label(
                banner == .offline ? "offline.banner.offline" : "offline.banner.serverUnreachable",
                systemImage: banner == .offline ? "wifi.slash" : "exclamationmark.icloud",
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.9))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Compact connectivity indicator for navigation bars, where a full-width banner would cover the header.
struct OfflineStatusPill: View {
    @Environment(OfflineCoordinator.self) private var offlineCoordinator

    var body: some View {
        if let banner = offlineCoordinator.banner {
            Label(
                banner == .offline ? "offline.banner.offline" : "offline.banner.serverUnreachable",
                systemImage: banner == .offline ? "wifi.slash" : "exclamationmark.icloud",
            )
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.9), in: Capsule(style: .continuous))
            .fixedSize()
        }
    }
}

struct OfflineUnavailableView: View {
    var body: some View {
        ContentUnavailableView(
            "offline.unavailable",
            systemImage: "wifi.slash",
            description: Text("offline.unavailable.description"),
        )
    }
}

private struct OfflineConnectivityChangeModifier: ViewModifier {
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    let server: ServerIdentity
    let action: (Bool) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: offlineCoordinator.isUnreachable(server)) { _, isUnreachable in
            action(isUnreachable)
        }
    }
}

struct OfflineDimmingModifier: ViewModifier {
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @Environment(DownloadManager.self) private var downloadManager
    let media: MediaDisplayItem
    let server: ServerIdentity

    func body(content: Content) -> some View {
        let isUnavailable = offlineCoordinator.isUnreachable(server) && !downloadManager.isAvailableOffline(media)
        content
            .opacity(isUnavailable ? 0.4 : 1)
            .grayscale(isUnavailable ? 1 : 0)
            .accessibilityHint(isUnavailable ? Text("offline.unavailable") : Text(verbatim: ""))
    }
}

private struct OfflineUnavailableModifier: ViewModifier {
    @Environment(OfflineCoordinator.self) private var offlineCoordinator

    func body(content: Content) -> some View {
        if offlineCoordinator.isFullyOffline {
            OfflineUnavailableView()
        } else {
            content
        }
    }
}

extension View {
    /// Runs `action` when the server becomes unreachable (`true`) or reachable again (`false`).
    func onConnectivityChange(of server: ServerIdentity, perform action: @escaping (Bool) -> Void) -> some View {
        modifier(OfflineConnectivityChangeModifier(server: server, action: action))
    }

    /// Replaces features that need the server (favorites, Live TV, Seerr…) by an explicit empty state offline.
    func unavailableWhenOffline() -> some View {
        modifier(OfflineUnavailableModifier())
    }

    /// Greys out an item that is known locally but cannot be played while its server is unreachable.
    func dimmedWhenUnavailableOffline(_ media: MediaItem) -> some View {
        modifier(OfflineDimmingModifier(media: .playable(media), server: media.identity.server))
    }

    func offlineBanner() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            OfflineBanner()
        }
    }
}

private struct AccountRemovalPromptModifier: ViewModifier {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(DownloadManager.self) private var downloadManager
    @Bindable var flow: AccountRemovalFlow

    func body(content: Content) -> some View {
        content.alert(
            "settings.accounts.remove.downloads.title",
            // Dismissal is handled by the buttons: cancelling here would clear the account before `finish` runs.
            isPresented: Binding(
                get: { flow.downloadsPrompt != nil },
                set: { _ in },
            ),
            presenting: flow.downloadsPrompt,
        ) { _ in
            Button("settings.accounts.remove.downloads.keep") {
                Task {
                    await flow.finish(
                        deleteDownloads: false,
                        sessionManager: sessionManager,
                        downloadManager: downloadManager,
                    )
                }
            }
            Button("settings.accounts.remove.downloads.delete", role: .destructive) {
                Task {
                    await flow.finish(
                        deleteDownloads: true,
                        sessionManager: sessionManager,
                        downloadManager: downloadManager,
                    )
                }
            }
            Button("common.actions.cancel", role: .cancel) {
                flow.cancel()
            }
        } message: { prompt in
            let size = ByteCountFormatter.string(fromByteCount: prompt.bytes, countStyle: .file)
            if prompt.hasUnsyncedProgress {
                Text("settings.accounts.remove.downloads.message.unsynced \(prompt.count) \(size)")
            } else {
                Text("settings.accounts.remove.downloads.message \(prompt.count) \(size)")
            }
        }
    }
}

extension View {
    /// Asks whether the downloads of an account being removed should be deleted too.
    func accountRemovalPrompt(_ flow: AccountRemovalFlow) -> some View {
        modifier(AccountRemovalPromptModifier(flow: flow))
    }
}
