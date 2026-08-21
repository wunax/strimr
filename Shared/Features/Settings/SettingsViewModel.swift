import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    private let settingsManager: SettingsManager
    let seekOptions = [5, 10, 15, 30, 45, 60]
    let nextEpisodeAutoplayOptions = NextEpisodeAutoplay.allCases
    let subtitleFontSizeOptions = [12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40]
    let subtitleTextColorOptions = SubtitleTextColor.allCases
    let subtitleFontWeightOptions = SubtitleFontWeight.allCases
    let subtitleBackgroundStrengthOptions = SubtitleBackgroundStrength.allCases
    let subtitleEdgeStyleOptions = SubtitleEdgeStyle.allCases
    let subtitleVerticalPositionOptions = SubtitleVerticalPosition.allCases

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    var nextEpisodeAutoplayBinding: Binding<NextEpisodeAutoplay> {
        Binding(
            get: { self.settingsManager.playback.nextEpisodeAutoplay },
            set: { self.settingsManager.setNextEpisodeAutoplay($0) },
        )
    }

    var autoSkipIntrosBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.autoSkipIntros },
            set: { self.settingsManager.setAutoSkipIntros($0) },
        )
    }

    var autoSkipCreditsBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.autoSkipCredits },
            set: { self.settingsManager.setAutoSkipCredits($0) },
        )
    }

    var losslessAudioBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.losslessAudio },
            set: { self.settingsManager.setLosslessAudio($0) },
        )
    }

    var showChaptersOnTimelineBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.showChaptersOnTimeline },
            set: { self.settingsManager.setShowChaptersOnTimeline($0) },
        )
    }

    var showEndsAtTimeBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.showEndsAtTime },
            set: { self.settingsManager.setShowEndsAtTime($0) },
        )
    }

    var showClockBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.showClock },
            set: { self.settingsManager.setShowClock($0) },
        )
    }

    var showScrubThumbnailPreviewsBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.showScrubThumbnailPreviews },
            set: { self.settingsManager.setShowScrubThumbnailPreviews($0) },
        )
    }

    var generateMissingScrubThumbnailPreviewsBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.generateMissingScrubThumbnailPreviews },
            set: { self.settingsManager.setGenerateMissingScrubThumbnailPreviews($0) },
        )
    }

    var showsScrubThumbnailPreviews: Bool {
        settingsManager.playback.showScrubThumbnailPreviews
    }

    var rewindBinding: Binding<Int> {
        Binding(
            get: { self.settingsManager.playback.seekBackwardSeconds },
            set: { self.settingsManager.setSeekBackwardSeconds($0) },
        )
    }

    var fastForwardBinding: Binding<Int> {
        Binding(
            get: { self.settingsManager.playback.seekForwardSeconds },
            set: { self.settingsManager.setSeekForwardSeconds($0) },
        )
    }

    var subtitleFontSizeBinding: Binding<Int> {
        Binding(
            get: { self.settingsManager.playback.subtitleFontSize },
            set: { self.settingsManager.setSubtitleFontSize($0) },
        )
    }

    var styledASSSubtitlesBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.styledASSSubtitles },
            set: { self.settingsManager.setStyledASSSubtitles($0) },
        )
    }

    var subtitleTextColorBinding: Binding<SubtitleTextColor> {
        Binding(
            get: { self.settingsManager.playback.subtitleTextColor },
            set: { self.settingsManager.setSubtitleTextColor($0) },
        )
    }

    var subtitleFontWeightBinding: Binding<SubtitleFontWeight> {
        Binding(
            get: { self.settingsManager.playback.subtitleFontWeight },
            set: { self.settingsManager.setSubtitleFontWeight($0) },
        )
    }

    var subtitleBackgroundStrengthBinding: Binding<SubtitleBackgroundStrength> {
        Binding(
            get: { self.settingsManager.playback.subtitleBackgroundStrength },
            set: { self.settingsManager.setSubtitleBackgroundStrength($0) },
        )
    }

    var subtitleVerticalPositionBinding: Binding<SubtitleVerticalPosition> {
        Binding(
            get: { self.settingsManager.playback.subtitleVerticalPosition },
            set: { self.settingsManager.setSubtitleVerticalPosition($0) },
        )
    }

    var subtitleEdgeStyleBinding: Binding<SubtitleEdgeStyle> {
        Binding(
            get: { self.settingsManager.playback.subtitleEdgeStyle },
            set: { self.settingsManager.setSubtitleEdgeStyle($0) },
        )
    }

    func resetSubtitleAppearance() {
        settingsManager.resetSubtitleAppearance()
    }
}
