import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    private let settingsManager: SettingsManager
    let seekOptions = [5, 10, 15, 30, 45, 60]
    let playerOptions = PlaybackPlayer.allCases

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    var autoPlayNextBinding: Binding<Bool> {
        Binding(
            get: { self.settingsManager.playback.autoPlayNextEpisode },
            set: { self.settingsManager.setAutoPlayNextEpisode($0) }
        )
    }

    var rewindBinding: Binding<Int> {
        Binding(
            get: { self.settingsManager.playback.seekBackwardSeconds },
            set: { self.settingsManager.setSeekBackwardSeconds($0) }
        )
    }

    var fastForwardBinding: Binding<Int> {
        Binding(
            get: { self.settingsManager.playback.seekForwardSeconds },
            set: { self.settingsManager.setSeekForwardSeconds($0) }
        )
    }

    var playerBinding: Binding<PlaybackPlayer> {
        Binding(
            get: { self.settingsManager.playback.player },
            set: { self.settingsManager.setPlaybackPlayer($0) }
        )
    }
}
