import AetherEngine
import Foundation
@testable import Strimr
import Testing

struct AutomaticSubtitleSearchTests {
    private func account(language: String? = "fr", mode: AccountSubtitleMode = .fromFile) -> AccountPreferences {
        AccountPreferences(
            audioLanguage: nil,
            selectsAudioByLanguage: false,
            subtitleLanguage: language,
            subtitleMode: mode,
        )
    }

    private func rememberedTrack(language: String?, isForced: Bool = false) -> MediaSubtitlePreference {
        .track(
            streamIndex: nil,
            language: language,
            title: nil,
            codec: "srt",
            isForced: isForced,
            isHearingImpaired: nil,
        )
    }

    @Test func `the language remembered for the media comes first`() {
        let language = AutomaticSubtitleSearch.language(
            remembered: rememberedTrack(language: "spa"),
            account: account(),
            deviceLanguage: "de-DE",
        )
        #expect(language == "es")
    }

    @Test func `the account language comes before the device`() {
        let language = AutomaticSubtitleSearch.language(
            remembered: .serverDefault,
            account: account(),
            deviceLanguage: "de-DE",
        )
        #expect(language == "fr")
    }

    @Test func `the device language is the last resort`() {
        let language = AutomaticSubtitleSearch.language(
            remembered: nil,
            account: account(language: nil),
            deviceLanguage: "de-DE",
        )
        #expect(language == "de")
        #expect(AutomaticSubtitleSearch.language(remembered: nil, account: nil, deviceLanguage: "de-DE") == "de")
    }

    @Test func `subtitles turned off for the media are respected`() {
        let language = AutomaticSubtitleSearch.language(remembered: .off, account: account(), deviceLanguage: "fr")
        #expect(language == nil)
    }

    @Test func `a remembered forced track is respected`() {
        let language = AutomaticSubtitleSearch.language(
            remembered: rememberedTrack(language: "fr", isForced: true),
            account: account(),
            deviceLanguage: "fr",
        )
        #expect(language == nil)
    }

    @Test(arguments: [AccountSubtitleMode.off, .onlyForced])
    func `an account refusing full subtitles stops the search`(mode: AccountSubtitleMode) {
        let language = AutomaticSubtitleSearch.language(
            remembered: nil,
            account: account(mode: mode),
            deviceLanguage: "fr",
        )
        #expect(language == nil)
    }

    @Test(arguments: [AccountSubtitleMode.manual, .fromFile, .always, .smart])
    func `other account modes allow the search`(mode: AccountSubtitleMode) {
        let language = AutomaticSubtitleSearch.language(
            remembered: nil,
            account: account(mode: mode),
            deviceLanguage: "de",
        )
        #expect(language == "fr")
    }

    @Test func `a choice for this media overrides an account that turned subtitles off`() {
        let language = AutomaticSubtitleSearch.language(
            remembered: rememberedTrack(language: "fre"),
            account: account(language: "en", mode: .off),
            deviceLanguage: "de",
        )
        #expect(language == "fr")
    }

    @Test func `searches when no subtitle matches`() {
        #expect(AutomaticSubtitleSearch.isMissing(
            language: "fr",
            audioLanguage: "eng",
            subtitles: [.init(language: "eng", isForced: false)],
        ))
    }

    @Test func `an existing subtitle stops the search, even with another spelling`() {
        for spelling in ["fre", "fra", "fr", "fr-CA", "French", "Français"] {
            #expect(!AutomaticSubtitleSearch.isMissing(
                language: "fr",
                audioLanguage: "eng",
                subtitles: [.init(language: spelling, isForced: false)],
            ))
        }
    }

    @Test func `a forced subtitle does not count as existing`() {
        #expect(AutomaticSubtitleSearch.isMissing(
            language: "fr",
            audioLanguage: "eng",
            subtitles: [.init(language: "fre", isForced: true)],
        ))
    }

    @Test func `audio in the wanted language needs no subtitle`() {
        #expect(!AutomaticSubtitleSearch.isMissing(language: "fr", audioLanguage: "French", subtitles: []))
    }

    @Test(arguments: [nil, "", "und", "Unknown"])
    func `audio of unknown language does not start a search`(audioLanguage: String?) {
        #expect(!AutomaticSubtitleSearch.isMissing(language: "fr", audioLanguage: audioLanguage, subtitles: []))
    }

    @Test func `finds the new track in the wanted language`() throws {
        let old = subtitle("https://server.test/old.srt", language: "fre")
        let other = subtitle("https://server.test/other.srt", language: "eng")
        let new = subtitle("https://server.test/new.srt", language: "fre")

        let found = AutomaticSubtitleSearch.installedSubtitle(
            in: [old, other, new],
            previousURLs: [old.track.url],
            language: "fr",
        )
        #expect(try #require(found).track.url == new.track.url)
    }

    @Test func `accepts a new track without a language`() throws {
        let new = subtitle("https://server.test/new.srt", language: nil)
        let found = AutomaticSubtitleSearch.installedSubtitle(in: [new], previousURLs: [], language: "fr")
        #expect(try #require(found).track.url == new.track.url)
    }

    @Test func `does not fall back on a track already there`() {
        let old = subtitle("https://server.test/old.srt", language: "fre")
        let found = AutomaticSubtitleSearch.installedSubtitle(
            in: [old],
            previousURLs: [old.track.url],
            language: "fr",
        )
        #expect(found == nil)
    }

    private func subtitle(_ url: String, language: String?) -> PlayerExternalSubtitle {
        PlayerExternalSubtitle(
            track: ExternalSubtitleTrack(url: URL(string: url)!, language: language),
            providerStreamID: 1,
        )
    }
}

@MainActor
struct PlayerViewModelAutomaticSubtitleSearchTests {
    private final class Service: FakeMediaService {
        var results: [RemoteSubtitleResult] = []
        var searchedLanguages: [String] = []
        var installedIDs: [String] = []
        var refreshed: [PlayerExternalSubtitle] = []
        var audioLanguage = "eng"
        var onSearch: () async -> Void = {}

        override var supportsRemoteSubtitleSearch: Bool {
            true
        }

        override var authorization: MediaAuthorization {
            .plex(isAdministrator: true, allowsMediaDeletion: false)
        }

        override func prepare(
            media: MediaItem,
            resume _: Bool,
            quality: TranscodeQualityPreset,
            trackPreference _: MediaTrackPreference?,
            version _: MediaVersionRequest,
        ) async throws -> PlaybackPlan {
            PlaybackPlan(
                media: media,
                url: URL(string: "https://server.test/video.mkv")!,
                httpHeaders: [:],
                method: .directPlay,
                requestedQuality: quality,
                effectiveQuality: quality,
                qualityFallbackMessage: nil,
                mediaSourceID: nil,
                playSessionID: nil,
                transcodeSessionID: nil,
                initialPosition: nil,
                selectedAudioIndex: 1,
                selectedSubtitleIndex: nil,
                subtitleSelectionIsOff: false,
                tracks: [PlaybackTrack(
                    id: "1",
                    sourceIndex: 1,
                    kind: .audio,
                    isExternal: false,
                    title: "Audio",
                    name: nil,
                    language: audioLanguage,
                    codec: "aac",
                    isDefault: true,
                    isForced: false,
                    isHearingImpaired: false,
                )],
                externalSubtitles: [],
                chapters: [],
                skipSegments: [],
                scrubThumbnailSource: nil,
                versions: [],
                versionID: nil,
            )
        }

        override func searchSubtitles(
            itemID _: String,
            language: String,
            hearingImpaired _: Bool,
            forced _: Bool,
            title _: String?,
        ) async throws -> [RemoteSubtitleResult] {
            searchedLanguages.append(language)
            await onSearch()
            return results
        }

        override func installSubtitle(itemID _: String, result: RemoteSubtitleResult) async throws {
            installedIDs.append(result.id)
        }

        override func externalSubtitles(media _: MediaItem) async throws -> [PlayerExternalSubtitle] {
            refreshed
        }

        override func selectSubtitleTrack(id _: Int?, itemID _: String, versionID _: String?) async throws {}
    }

    private struct AccountPreferencesStub: AccountPreferencesService {
        var preferences = AccountPreferences(
            audioLanguage: nil,
            selectsAudioByLanguage: false,
            subtitleLanguage: "fr",
            subtitleMode: .fromFile,
        )

        var subtitleModes: [AccountSubtitleMode] {
            []
        }

        func load() async throws -> AccountPreferences {
            preferences
        }

        func apply(_: AccountPreferenceChange) async throws -> AccountPreferences {
            preferences
        }
    }

    private var enabledSettings: PlaybackSettings {
        var settings = PlaybackSettings()
        settings.automaticSubtitleSearch = true
        return settings
    }

    private func result(_ id: String, score: Double) -> RemoteSubtitleResult {
        RemoteSubtitleResult(id: id, title: id, language: "fre", codec: "srt", providerTitle: nil, matchScore: score)
    }

    private func loadedViewModel(_ service: Service) async -> PlayerViewModel {
        let server = ServerIdentity(provider: .jellyfin, id: "server-1")
        let services = MediaServices.fake(service, server: server)
        services.accountPreferences = AccountPreferencesStub()
        let media = MediaItem.make(id: "item-1", server: server)
        let queue = PlaybackQueue(
            id: UUID(),
            items: [PlaybackQueueItem(id: UUID(), media: media, providerQueueItemID: nil)],
            currentIndex: 0,
            isShuffled: false,
        )
        let viewModel = PlayerViewModel(queue: queue, services: services)
        await viewModel.load()
        return viewModel
    }

    @Test func `installs and returns the best ranked result`() async throws {
        let service = Service()
        service.results = [result("low", score: 1), result("high", score: 9)]
        let installed = try PlayerExternalSubtitle(
            track: ExternalSubtitleTrack(
                url: #require(URL(string: "https://server.test/new.srt")),
                language: "fre",
            ),
            providerStreamID: 5,
        )
        service.refreshed = [installed]
        let viewModel = await loadedViewModel(service)

        let outcome = await viewModel.searchMissingSubtitle(settings: enabledSettings)

        #expect(service.searchedLanguages == ["fr"])
        #expect(service.installedIDs == ["high"])
        guard case let .attached(subtitle, language) = outcome else {
            Issue.record("Expected an attached subtitle, got \(String(describing: outcome))")
            return
        }
        #expect(subtitle.providerStreamID == 5)
        #expect(language == "fr")
    }

    @Test func `does nothing while the setting is off`() async {
        let service = Service()
        let viewModel = await loadedViewModel(service)

        let outcome = await viewModel.searchMissingSubtitle(settings: PlaybackSettings())

        #expect(outcome == nil)
        #expect(service.searchedLanguages.isEmpty)
    }

    @Test func `does not search when the audio is already in the wanted language`() async {
        let service = Service()
        service.audioLanguage = "fre"
        let viewModel = await loadedViewModel(service)

        let outcome = await viewModel.searchMissingSubtitle(settings: enabledSettings)

        #expect(outcome == nil)
        #expect(service.searchedLanguages.isEmpty)
    }

    @Test func `reports an empty search`() async {
        let viewModel = await loadedViewModel(Service())

        guard case let .notFound(language) = await viewModel.searchMissingSubtitle(settings: enabledSettings) else {
            Issue.record("Expected no result")
            return
        }
        #expect(language == "fr")
    }

    @Test func `a subtitle chosen during the search cancels the install`() async {
        let service = Service()
        service.results = [result("only", score: 1)]
        let viewModel = await loadedViewModel(service)
        service.onSearch = {
            await viewModel.persistSubtitleStreamSelection(for: nil)
        }

        let outcome = await viewModel.searchMissingSubtitle(settings: enabledSettings)

        #expect(outcome == nil)
        #expect(service.installedIDs.isEmpty)
    }

    @Test func `a track the server did not add is a failure`() async {
        let service = Service()
        service.results = [result("only", score: 1)]
        let viewModel = await loadedViewModel(service)

        guard case .failed = await viewModel.searchMissingSubtitle(settings: enabledSettings) else {
            Issue.record("Expected a failure")
            return
        }
    }
}
