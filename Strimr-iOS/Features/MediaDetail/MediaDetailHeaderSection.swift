import GroupActivities
import Observation
import SwiftUI
import UIKit

struct MediaDetailHeaderSection: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @Environment(MediaServices.self) private var mediaServices
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @Bindable var viewModel: MediaDetailViewModel
    @Binding var isSummaryExpanded: Bool
    let heroHeight: CGFloat
    let onPlay: (String, MediaKind) -> Void
    let onPlayFromStart: (String, MediaKind) -> Void
    let onShuffle: (String, MediaKind) -> Void
    let onSelectParentSeries: () -> Void
    var onSearchSubtitles: () -> Void = {}
    @State private var isShowingShowDownloadSheet = false
    @State private var isShowingDownloadOptions = false
    @State private var isShowingFileInfo = false
    @State private var sharePlaySharingRequest: SharePlaySharingRequest?
    @State private var queuedDownloadCount = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            DetailHeroView(
                viewModel: viewModel,
                heroHeight: heroHeight,
                onSelectParentSeries: onSelectParentSeries,
            )

            VStack(alignment: .leading, spacing: 16) {
                // The title block straddles the bottom of the backdrop.
                Spacer().frame(height: heroHeight - LayoutMetrics.heroLogoMaxSize.height - 24)

                DetailHeroTitle(viewModel: viewModel)
                DetailActionsRow(
                    viewModel: viewModel,
                    isStartingSharePlay: isStartingSharePlay,
                    onPlay: onPlay,
                    onPlayFromStart: onPlayFromStart,
                    onShuffle: onShuffle,
                    onShowDownloadOptions: { isShowingDownloadOptions = true },
                    onShowShowDownloadSheet: { isShowingShowDownloadSheet = true },
                    onShowFileInfo: { isShowingFileInfo = true },
                    onStartSharePlay: startSharePlay,
                )
                DetailPlaybackCard(
                    viewModel: viewModel,
                    isServerUnreachable: offlineCoordinator.isUnreachable(mediaServices.identity),
                    onSearchSubtitles: onSearchSubtitles,
                )

                synopsis

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if let watchActionErrorMessage = viewModel.watchActionErrorMessage {
                    Label(watchActionErrorMessage, systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                }

                if let favoriteActionErrorMessage = viewModel.favoriteActionErrorMessage {
                    Label(favoriteActionErrorMessage, systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                }

                if let trackSelectionErrorMessage = viewModel.trackSelectionErrorMessage {
                    Label(trackSelectionErrorMessage, systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                }

                if viewModel.isLoading {
                    ProgressView("media.detail.updating")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sensoryFeedback(.success, trigger: viewModel.confirmedActionCount)
        .sensoryFeedback(.success, trigger: queuedDownloadCount)
        .sensoryFeedback(.error, trigger: viewModel.watchActionErrorMessage) { _, message in message != nil }
        .sensoryFeedback(.error, trigger: viewModel.favoriteActionErrorMessage) { _, message in message != nil }
        .sheet(isPresented: $isShowingShowDownloadSheet) {
            NavigationStack {
                ShowDownloadSelectionSheet(
                    viewModel: viewModel,
                    services: mediaServices,
                    defaultQuality: settingsManager.downloads.qualityPreset,
                    onSubmitSelection: { episodeIDs, quality, tracks, version in
                        for episodeID in episodeIDs {
                            await downloadManager.enqueueItem(
                                itemID: episodeID,
                                quality: quality,
                                tracks: tracks,
                                version: version,
                                services: mediaServices,
                            )
                        }
                        queuedDownloadCount += 1
                    },
                    statusForIdentity: downloadManager.status,
                )
            }
        }
        .sheet(isPresented: $isShowingDownloadOptions) {
            DownloadConfirmationSheet(
                itemID: viewModel.media.id,
                kind: viewModel.media.mediaKind,
                services: mediaServices,
                defaultQuality: settingsManager.downloads.qualityPreset,
            ) { quality, tracks, version in
                if viewModel.media.mediaKind == .season {
                    await downloadManager.enqueueItems(
                        itemID: viewModel.media.id,
                        kind: .season,
                        quality: quality,
                        tracks: tracks,
                        version: version,
                        services: mediaServices,
                    )
                } else {
                    await downloadManager.enqueueItem(
                        itemID: viewModel.media.id,
                        quality: quality,
                        tracks: tracks,
                        version: version,
                        services: mediaServices,
                    )
                }
                queuedDownloadCount += 1
            }
        }
        .sheet(isPresented: $isShowingFileInfo) {
            MediaFileInfoView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $sharePlaySharingRequest, onDismiss: {
            Task { await sharePlayCoordinator.sharingPresentationDidEnd() }
        }) { request in
            SharePlaySharingControllerView(controller: request.controller)
                .task {
                    let result = await request.controller.result
                    handleSharingResult(result, for: request.activity)
                }
        }
        .alert(
            "sharePlay.error.title",
            isPresented: Binding(
                get: { sharePlayCoordinator.errorMessage != nil },
                set: {
                    if !$0 {
                        sharePlayCoordinator.errorMessage = nil
                    }
                },
            ),
        ) {
            Button("common.actions.done") {
                sharePlayCoordinator.errorMessage = nil
            }
        } message: {
            Text(sharePlayCoordinator.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var synopsis: some View {
        if viewModel.media.mediaItem.shouldHideSpoilerSummary(at: settingsManager.interface.spoilerProtection) {
            Label("media.spoilerProtection.summaryHidden", systemImage: "eye.slash")
                .font(.body)
                .foregroundStyle(.textSecondary)
        } else if let summaryText {
            VStack(alignment: .leading, spacing: 8) {
                summaryText
                    .font(.body)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(isSummaryExpanded ? nil : 3)

                Button(action: { isSummaryExpanded.toggle() }) {
                    Text(isSummaryExpanded ? "common.actions.showLess" : "common.actions.readMore")
                        .font(.facts)
                        .fontWeight(.semibold)
                        .foregroundStyle(.textPrimary)
                }
            }
        }
    }

    /// The tagline leads the synopsis in semibold instead of taking a line of its own.
    private var summaryText: Text? {
        let tagline = viewModel.media.tagline.flatMap { $0.isEmpty ? nil : $0 }
        let summary = viewModel.media.summary.flatMap { $0.isEmpty ? nil : $0 }
        switch (tagline, summary) {
        case let (tagline?, summary?):
            return Text(verbatim: tagline + " ").fontWeight(.semibold).foregroundStyle(.textPrimary)
                + Text(verbatim: summary)
        case let (tagline?, nil):
            return Text(verbatim: tagline).fontWeight(.semibold).foregroundStyle(.textPrimary)
        case let (nil, summary?):
            return Text(verbatim: summary)
        case (nil, nil):
            return nil
        }
    }

    private var isStartingSharePlay: Bool {
        sharePlayCoordinator.isActivating || sharePlaySharingRequest != nil
    }

    private func startSharePlay() {
        guard
            let ratingKey = viewModel.primaryActionRatingKey,
            let playbackType = viewModel.primaryActionType,
            let item = viewModel.primaryActionItem, let activity = sharePlayCoordinator.makeActivity(
                ratingKey: ratingKey,
                type: playbackType,
                title: item.primaryLabel,
                initialPosition: viewModel.primaryActionInitialPosition,
                server: viewModel.server,
            ) else { return }

        if sharePlayCoordinator.isEligibleForGroupSession {
            Task { await sharePlayCoordinator.activate(activity) }
            return
        }

        do {
            let controller = try GroupActivitySharingController(activity)
            sharePlayCoordinator.sharingDidStart(activity)
            sharePlaySharingRequest = SharePlaySharingRequest(
                activity: activity,
                controller: controller,
            )
        } catch {
            guard !error.isCancellation else { return }
            ErrorReporter.capture(error)
            sharePlayCoordinator.errorMessage = String(localized: "sharePlay.error.unavailable")
        }
    }

    private func handleSharingResult(
        _ result: GroupActivitySharingResult,
        for activity: StrimrWatchActivity,
    ) {
        if result == .cancelled {
            sharePlayCoordinator.sharingDidCancel(activity)
        }
        sharePlaySharingRequest = nil
    }
}

private struct SharePlaySharingRequest: Identifiable {
    let activity: StrimrWatchActivity
    let controller: GroupActivitySharingController

    var id: UUID {
        activity.activityID
    }
}
