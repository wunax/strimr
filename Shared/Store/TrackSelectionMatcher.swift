import Foundation

struct TrackSelectionMatchDescriptor {
    let exactIdentifiers: [Int]
    let language: String?
    let title: String?
    let displayTitle: String?
    let codec: String?
    let isForced: Bool?
    let isHearingImpaired: Bool?
}

enum TrackSelectionMatcher {
    static func bestAudioMatch<Candidate>(
        preference: MediaTrackPreference,
        candidates: [Candidate],
        descriptor: (Candidate) -> TrackSelectionMatchDescriptor,
    ) -> Candidate? {
        if let streamIndex = preference.audioStreamIndex,
           let exact = candidates.first(where: {
               descriptor($0).exactIdentifiers.contains(streamIndex)
           })
        {
            return exact
        }

        guard preference.audioLanguage != nil
            || preference.audioTitle != nil
            || preference.audioCodec != nil
        else {
            return nil
        }

        let languageCandidates = candidates.filter { candidate in
            guard let language = preference.audioLanguage else { return true }
            return normalized(descriptor(candidate).language) == normalized(language)
        }

        return bestCandidate(languageCandidates) { candidate in
            let track = descriptor(candidate)
            var score = 0
            if let language = preference.audioLanguage,
               normalized(track.language) == normalized(language)
            {
                score += 4
            }
            if let title = preference.audioTitle,
               normalized(track.displayTitle) == normalized(title)
                   || normalized(track.title) == normalized(title)
            {
                score += 3
            }
            if let codec = preference.audioCodec,
               normalized(track.codec) == normalized(codec)
            {
                score += 2
            }
            if let hearingImpaired = preference.audioIsHearingImpaired,
               track.isHearingImpaired == hearingImpaired
            {
                score += 1
            }
            return score
        }
    }

    static func bestSubtitleMatch<Candidate>(
        preference: MediaSubtitlePreference,
        candidates: [Candidate],
        descriptor: (Candidate) -> TrackSelectionMatchDescriptor,
    ) -> Candidate? {
        guard case let .track(streamIndex, language, title, codec, isForced, isHearingImpaired) = preference else {
            return nil
        }

        if let streamIndex,
           let exact = candidates.first(where: {
               descriptor($0).exactIdentifiers.contains(streamIndex)
           })
        {
            return exact
        }

        guard language != nil || title != nil || !codec.isEmpty else { return nil }

        let languageCandidates = candidates.filter { candidate in
            guard let language else { return true }
            return normalized(descriptor(candidate).language) == normalized(language)
        }

        return bestCandidate(languageCandidates) { candidate in
            let track = descriptor(candidate)
            var score = 0
            if let language,
               normalized(track.language) == normalized(language)
            {
                score += 4
            }
            if let title,
               normalized(track.displayTitle) == normalized(title)
                   || normalized(track.title) == normalized(title)
            {
                score += 3
            }
            if !codec.isEmpty, normalized(track.codec) == normalized(codec) {
                score += 2
            }
            if track.isForced == isForced {
                score += 1
            }
            if let isHearingImpaired,
               track.isHearingImpaired == isHearingImpaired
            {
                score += 1
            }
            return score
        }
    }

    private static func bestCandidate<Candidate>(
        _ candidates: [Candidate],
        score: (Candidate) -> Int,
    ) -> Candidate? {
        var best: Candidate?
        var bestScore = 0
        for candidate in candidates {
            let candidateScore = score(candidate)
            guard candidateScore > bestScore else { continue }
            best = candidate
            bestScore = candidateScore
        }
        return best
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

extension MediaTrackMetadata {
    var trackSelectionMatchDescriptor: TrackSelectionMatchDescriptor {
        TrackSelectionMatchDescriptor(
            exactIdentifiers: [id, sourceIndex].compactMap(\.self),
            language: language,
            title: title,
            displayTitle: displayTitle,
            codec: codec,
            isForced: isForced,
            isHearingImpaired: isHearingImpaired,
        )
    }
}
