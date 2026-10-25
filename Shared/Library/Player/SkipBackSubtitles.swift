import Foundation

/// Shows a full subtitle track after a short skip back, like tvOS's Show on Skip Back, then puts the previous
/// state back (no subtitles or forced only) once playback passes the point where the user skipped from.
struct SkipBackSubtitles: Equatable {
    struct Track: Equatable {
        let id: Int
        let language: String?
        let isForced: Bool
        let isCommentary: Bool
    }

    struct Window: Equatable {
        var returnPosition: Double
        let previousTrackID: Int?
        /// The seek lands asynchronously, so positions are ignored until one shows playback went back.
        var isArmed = false
    }

    struct Restore: Equatable {
        let trackID: Int?
    }

    static let maximumRewind = 30.0

    private(set) var window: Window?

    /// The track the user picked, even while the window temporarily shows another one.
    func userTrackID(displayedTrackID: Int?) -> Int? {
        window.map(\.previousTrackID) ?? displayedTrackID
    }

    /// Returns the track to show, or nil when nothing should change.
    mutating func skipBack(
        from origin: Double,
        to target: Double,
        selectedTrackID: Int?,
        tracks: [Track],
        audioLanguage: String?,
    ) -> Int? {
        if var window {
            guard window.returnPosition - target <= Self.maximumRewind else { return nil }
            window.returnPosition = max(window.returnPosition, origin)
            self.window = window
            return nil
        }

        guard origin > target, origin - target <= Self.maximumRewind else { return nil }
        let selected = selectedTrackID.flatMap { id in tracks.first { $0.id == id } }
        if let selected, !selected.isForced {
            return nil
        }

        let languages = [selected?.language, audioLanguage].compactMap(Self.normalizedLanguage)
        let fullTracks = tracks.filter { !$0.isForced && !$0.isCommentary }
        let match = languages.lazy.compactMap { language in
            fullTracks.first { Self.normalizedLanguage($0.language) == language }
        }.first
        guard let track = match ?? fullTracks.first else { return nil }

        window = Window(returnPosition: origin, previousTrackID: selectedTrackID)
        return track.id
    }

    /// Returns the track to restore once playback passes the return position.
    mutating func observe(position: Double) -> Restore? {
        guard var window else { return nil }
        if !window.isArmed {
            guard position < window.returnPosition else { return nil }
            window.isArmed = true
            self.window = window
        }
        guard position >= window.returnPosition else { return nil }
        self.window = nil
        return Restore(trackID: window.previousTrackID)
    }

    /// Returns the track to restore when a skip forward reaches the return position, since playback then
    /// never passes below it to arm the window.
    mutating func skipForward(to target: Double) -> Restore? {
        guard let window, target >= window.returnPosition else { return nil }
        return end()
    }

    /// Ends the window and returns the track to restore, if one was open.
    mutating func end() -> Restore? {
        guard let window else { return nil }
        self.window = nil
        return Restore(trackID: window.previousTrackID)
    }

    mutating func cancel() {
        window = nil
    }

    private static let bibliographicLanguageCodes = [
        "alb": "sq", "arm": "hy", "baq": "eu", "bur": "my", "chi": "zh", "cze": "cs", "dut": "nl",
        "fre": "fr", "geo": "ka", "ger": "de", "gre": "el", "ice": "is", "mac": "mk", "mao": "mi",
        "may": "ms", "per": "fa", "rum": "ro", "slo": "sk", "tib": "bo", "wel": "cy",
    ]

    static func normalizedLanguage(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty, value != "und"
        else {
            return nil
        }
        if let code = bibliographicLanguageCodes[value] {
            return code
        }
        return Locale.Language(identifier: value).languageCode?.identifier(.alpha2) ?? value
    }
}
