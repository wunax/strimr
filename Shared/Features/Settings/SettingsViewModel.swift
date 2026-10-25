import AetherEngine
import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    private let settingsManager: SettingsManager
    let seekOptions = [5, 10, 15, 30, 45, 60]
    let nextEpisodeAutoplayOptions = NextEpisodeAutoplay.allCases
    #if os(tvOS)
        let subtitleFontSizeOptions = Array(stride(from: 12, through: 80, by: 2))
    #else
        let subtitleFontSizeOptions = Array(stride(from: 12, through: 40, by: 2))
    #endif
    let subtitleTextColorOptions = SubtitleTextColor.allCases
    let subtitleBrightnessOptions = SubtitleBrightness.allCases
    let subtitleFontWeightOptions = SubtitleFontWeight.allCases
    let subtitleBackgroundStrengthOptions = SubtitleBackgroundStrength.allCases
    let subtitleEdgeStyleOptions = SubtitleEdgeStyle.allCases
    let subtitleVerticalPositionOptions = SubtitleVerticalPosition.allCases

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    var qualityPresetBinding: Binding<TranscodeQualityPreset> {
        Binding(
            get: { self.settingsManager.playback.qualityPreset },
            set: { self.settingsManager.setPlaybackQualityPreset($0) },
        )
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

    var autoSkipCommercialsBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.autoSkipCommercials },
            set: { self.settingsManager.setAutoSkipCommercials($0) },
        )
    }

    var losslessAudioBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.losslessAudio },
            set: { self.settingsManager.setLosslessAudio($0) },
        )
    }

    var isSpatialAudioAvailable: Bool {
        guard #available(iOS 26.0, tvOS 26.0, macOS 26.0, *) else { return false }
        return AetherEngine.OptionalComponent.trueHDObjectAudio.isBuiltIn
            || AetherEngine.OptionalComponent.dtsxObjectAudio.isBuiltIn
    }

    /// The widest bed loses no object position; the receiver folds it down to its own speakers.
    var spatialAudioBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.spatialAudioLayout != nil },
            set: { self.settingsManager.setSpatialAudioLayout($0 ? .l916 : nil) },
        )
    }

    var rememberTrackSelectionsBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.rememberTrackSelections },
            set: { self.settingsManager.setRememberTrackSelections($0) },
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

    var showInfoWhenPausedBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.showInfoWhenPaused },
            set: { self.settingsManager.setShowInfoWhenPaused($0) },
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

    var doubleTapToSeekBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.doubleTapToSeek },
            set: { self.settingsManager.setDoubleTapToSeek($0) },
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

    var showSubtitlesOnSkipBackBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.showSubtitlesOnSkipBack },
            set: { self.settingsManager.setShowSubtitlesOnSkipBack($0) },
        )
    }

    var subtitleTextColorBinding: Binding<SubtitleTextColor> {
        Binding(
            get: { self.settingsManager.playback.subtitleTextColor },
            set: { self.settingsManager.setSubtitleTextColor($0) },
        )
    }

    var subtitleBrightnessBinding: Binding<SubtitleBrightness> {
        Binding(
            get: { self.settingsManager.playback.subtitleBrightness },
            set: { self.settingsManager.setSubtitleBrightness($0) },
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

extension SettingsViewModel {
    /// Known players are listed when installed, or when already selected so the user can switch away.
    var externalPlayerOptions: [ExternalPlayerOption] {
        let selected = settingsManager.playback.externalPlayer
        let known = ExternalPlayerID.allCases.filter { player in
            player.isSupported(on: .current)
                && (selected == .known(player) || ExternalPlayerApps.isInstalled(player))
        }
        return [.builtIn] + known.map(ExternalPlayerOption.known) + [.custom]
    }

    var selectedExternalPlayerOption: ExternalPlayerOption {
        switch settingsManager.playback.resolvedExternalPlayer {
        case let .known(player): .known(player)
        case .custom: .custom
        case nil: .builtIn
        }
    }

    var customExternalPlayer: CustomExternalPlayer? {
        settingsManager.playback.customExternalPlayer.flatMap { $0.isValid ? $0 : nil }
    }

    func title(for option: ExternalPlayerOption) -> String {
        switch option {
        case .builtIn:
            String(localized: "settings.playback.externalPlayer.builtIn")
        case let .known(player):
            player.displayName
        case .custom:
            customExternalPlayer?.name ?? String(localized: "settings.playback.externalPlayer.custom")
        }
    }

    /// Returns false when the custom player must be defined first.
    @discardableResult
    func selectExternalPlayer(_ option: ExternalPlayerOption) -> Bool {
        switch option {
        case .builtIn:
            settingsManager.setExternalPlayer(nil)
        case let .known(player):
            settingsManager.setExternalPlayer(.known(player))
        case .custom:
            guard customExternalPlayer != nil else { return false }
            settingsManager.setExternalPlayer(.custom)
        }
        return true
    }

    func saveCustomExternalPlayer(_ player: CustomExternalPlayer) {
        settingsManager.setCustomExternalPlayer(player)
    }

    var externalPlayerFooter: String? {
        settingsManager.playback.resolvedExternalPlayer.map {
            String(localized: "settings.playback.externalPlayer.footer \($0.displayName)")
        }
    }
}
