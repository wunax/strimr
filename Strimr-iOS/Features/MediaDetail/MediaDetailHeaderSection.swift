import GroupActivities
import Observation
import SwiftUI
import UIKit

struct MediaDetailHeaderSection: View {
    @Environment(DownloadManager.self) private var downloadManager
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            DetailHeroView(
                viewModel: viewModel,
                heroHeight: heroHeight,
                onSelectParentSeries: onSelectParentSeries,
            )

            VStack(alignment: .leading, spacing: 16) {
                Spacer().frame(height: heroHeight - 40)

                headerSection
                DetailActionsRow(
                    viewModel: viewModel,
                    isStartingSharePlay: isStartingSharePlay,
                    onPlay: onPlay,
                    onPlayFromStart: onPlayFromStart,
                    onShuffle: onShuffle,
                    onSearchSubtitles: onSearchSubtitles,
                    onShowDownloadOptions: { isShowingDownloadOptions = true },
                    onShowShowDownloadSheet: { isShowingShowDownloadSheet = true },
                    onShowFileInfo: { isShowingFileInfo = true },
                    onStartSharePlay: startSharePlay,
                )
                badgesSection
                ratingsSection

                if let tagline = viewModel.media.tagline, !tagline.isEmpty {
                    Text(tagline)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                if viewModel.media.mediaItem.shouldHideSpoilerSummary(
                    at: settingsManager.interface.spoilerProtection,
                ) {
                    Label("media.spoilerProtection.summaryHidden", systemImage: "eye.slash")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else if let summary = viewModel.media.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(isSummaryExpanded ? nil : 3)

                        Button(action: { isSummaryExpanded.toggle() }) {
                            Text(isSummaryExpanded ? "common.actions.showLess" : "common.actions.readMore")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .tint(.brandSecondary)
                        }
                        .tint(.accentColor)
                    }
                }

                DetailFactsSection(viewModel: viewModel)

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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.detailPrimaryLabel)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let secondary = viewModel.detailSecondaryLabel {
                Text(secondary)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let tertiary = viewModel.detailTertiaryLabel {
                Text(tertiary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var badgesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let year = viewModel.yearText {
                    badge(text: year)
                }

                if let runtime = viewModel.runtimeText {
                    badge(text: runtime, systemImage: "clock")
                }

                if let contentRating = viewModel.media.contentRating {
                    badge(text: contentRating)
                }

                if let versionCount = viewModel.versionCountBadge {
                    badge(
                        text: String(localized: "media.versions.count \(versionCount)"),
                        systemImage: "film.stack",
                    )
                }
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var ratingsSection: some View {
        if !viewModel.media.ratings.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.media.ratings.enumerated()), id: \.offset) { _, rating in
                        MediaRatingLabel(rating: rating, iconHeight: 16)
                            .font(.footnote)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func badge(text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var isStartingSharePlay: Bool {
        sharePlayCoordinator.isActivating || sharePlaySharingRequest != nil
    }

    private func startSharePlay() {
        guard
            let ratingKey = viewModel.primaryActionRatingKey,
            let playbackType = viewModel.primaryActionType,
            let item = viewModel.primaryActionItem
        else { return }
        guard let activity = sharePlayCoordinator.makeActivity(
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
