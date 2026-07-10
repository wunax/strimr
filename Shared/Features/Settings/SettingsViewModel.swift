import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    private let settingsManager: SettingsManager
    let seekOptions = [5, 10, 15, 30, 45, 60]
    let subtitleFontSizeOptions = [12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40]

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    var autoPlayNextBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.autoPlayNextEpisode },
            set: { self.settingsManager.setAutoPlayNextEpisode($0) },
        )
    }

    var losslessAudioBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.losslessAudio },
            set: { self.settingsManager.setLosslessAudio($0) },
        )
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
}
