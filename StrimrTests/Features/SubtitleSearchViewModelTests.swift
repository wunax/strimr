import Foundation
@testable import Strimr
import Testing

@MainActor
struct SubtitleSearchViewModelTests {
    private final class SubtitleService: FakeMediaService {
        var advancedSearch = true
        var holdsSearches = false
        private(set) var searches: [SubtitleSearchViewModel.SearchOptions] = []
        private var held: [CheckedContinuation<Void, Never>] = []

        override var supportsAdvancedSubtitleSearch: Bool {
            advancedSearch
        }

        var heldCount: Int {
            held.count
        }

        override func searchSubtitles(
            itemID _: String,
            language: String,
            hearingImpaired: Bool,
            forced: Bool,
            title _: String?,
        ) async throws -> [RemoteSubtitleResult] {
            searches.append(.init(language: language, hearingImpaired: hearingImpaired, forced: forced))
            if holdsSearches {
                await withCheckedContinuation { held.append($0) }
            }
            return [RemoteSubtitleResult(
                id: language,
                title: language,
                language: language,
                codec: "srt",
                providerTitle: nil,
            )]
        }

        func release(_ index: Int) {
            held[index].resume()
        }
    }

    private struct AccountPreferencesStub: AccountPreferencesService {
        var subtitleLanguage: String?

        var subtitleModes: [AccountSubtitleMode] {
            []
        }

        func load() async throws -> AccountPreferences {
            AccountPreferences(
                audioLanguage: nil,
                selectsAudioByLanguage: false,
                subtitleLanguage: subtitleLanguage,
                subtitleMode: .fromFile,
            )
        }

        func apply(_: AccountPreferenceChange) async throws -> AccountPreferences {
            try await load()
        }
    }

    private func viewModel(
        _ service: SubtitleService,
        preferences: SubtitleSearchPreferences = SubtitleSearchPreferences(),
        accountSubtitleLanguage: String? = nil,
        onPreferencesChange: @escaping (SubtitleSearchPreferences) -> Void = { _ in },
    ) -> SubtitleSearchViewModel {
        let services = MediaServices.fake(service)
        services.accountPreferences = AccountPreferencesStub(subtitleLanguage: accountSubtitleLanguage)
        return SubtitleSearchViewModel(
            itemID: "item",
            services: services,
            preferences: preferences,
            onPreferencesChange: onPreferencesChange,
        )
    }

    @Test func `opening searches with the remembered options`() async {
        let service = SubtitleService()
        let model = viewModel(
            service,
            preferences: SubtitleSearchPreferences(language: "fr", hearingImpaired: true, forced: true),
        )

        await model.searchIfNeeded()

        #expect(service.searches == [.init(language: "fr", hearingImpaired: true, forced: true)])
        #expect(model.results.map(\.id) == ["fr"])
    }

    @Test func `reappearing does not repeat a completed search`() async {
        let service = SubtitleService()
        let model = viewModel(service, preferences: SubtitleSearchPreferences(language: "fr"))

        await model.searchIfNeeded()
        await model.searchIfNeeded()

        #expect(service.searches.count == 1)
    }

    @Test func `a changed language searches again and is remembered`() async {
        let service = SubtitleService()
        var saved: [SubtitleSearchPreferences] = []
        let model = viewModel(service, preferences: SubtitleSearchPreferences(language: "fr")) { saved.append($0) }

        await model.searchIfNeeded()
        #expect(saved.isEmpty)

        model.selectedLanguage = "de"
        await model.searchIfNeeded()

        #expect(model.results.map(\.id) == ["de"])
        #expect(saved == [SubtitleSearchPreferences(language: "de")])
    }

    @Test func `the device language is not saved until another one is chosen`() async {
        var saved: [SubtitleSearchPreferences] = []
        let model = viewModel(SubtitleService()) { saved.append($0) }

        await model.searchIfNeeded()

        #expect(saved.isEmpty)
    }

    @Test func `opening without a remembered language searches in the account language`() async {
        let service = SubtitleService()
        var saved: [SubtitleSearchPreferences] = []
        let model = viewModel(service, accountSubtitleLanguage: "rum") { saved.append($0) }

        await model.searchIfNeeded()

        #expect(model.selectedLanguage == "ro")
        #expect(service.searches.map(\.language) == ["ro"])
        #expect(saved.isEmpty)
    }

    @Test func `a remembered language wins over the account language`() async {
        let service = SubtitleService()
        let model = viewModel(
            service,
            preferences: SubtitleSearchPreferences(language: "fr"),
            accountSubtitleLanguage: "ro",
        )

        await model.searchIfNeeded()

        #expect(service.searches.map(\.language) == ["fr"])
    }

    @Test func `a language other than the account one is remembered`() async {
        var saved: [SubtitleSearchPreferences] = []
        let model = viewModel(SubtitleService(), accountSubtitleLanguage: "ro") { saved.append($0) }
        await model.searchIfNeeded()

        model.selectedLanguage = "de"
        await model.searchIfNeeded()

        #expect(saved == [SubtitleSearchPreferences(language: "de")])
    }

    @Test func `picking the account language again stops remembering a language`() async {
        var saved: [SubtitleSearchPreferences] = []
        let model = viewModel(
            SubtitleService(),
            preferences: SubtitleSearchPreferences(language: "pt"),
            accountSubtitleLanguage: "ro",
        ) { saved.append($0) }
        await model.searchIfNeeded()
        #expect(model.selectedLanguage == "pt")

        model.selectedLanguage = "ro"
        await model.searchIfNeeded()
        #expect(saved == [SubtitleSearchPreferences()])

        let reopened = viewModel(SubtitleService(), preferences: saved[0], accountSubtitleLanguage: "de")
        await reopened.searchIfNeeded()

        #expect(reopened.selectedLanguage == "de")
    }

    @Test func `servers without advanced options ignore but keep the saved ones`() async {
        let service = SubtitleService()
        service.advancedSearch = false
        var saved: [SubtitleSearchPreferences] = []
        let model = viewModel(
            service,
            preferences: SubtitleSearchPreferences(language: "fr", hearingImpaired: true, forced: true),
        ) { saved.append($0) }

        await model.searchIfNeeded()
        #expect(service.searches == [.init(language: "fr", hearingImpaired: false, forced: false)])

        model.selectedLanguage = "de"
        await model.searchIfNeeded()

        #expect(saved == [SubtitleSearchPreferences(language: "de", hearingImpaired: true, forced: true)])
    }

    @Test func `a slower earlier search does not replace newer results`() async {
        let service = SubtitleService()
        service.holdsSearches = true
        let model = viewModel(service, preferences: SubtitleSearchPreferences(language: "fr"))

        let first = Task { await model.search() }
        while service.heldCount < 1 {
            await Task.yield()
        }
        model.selectedLanguage = "de"
        let second = Task { await model.search() }
        while service.heldCount < 2 {
            await Task.yield()
        }

        service.release(1)
        await second.value
        #expect(!model.isSearching)
        service.release(0)
        await first.value

        #expect(model.results.map(\.id) == ["de"])
        #expect(!model.isSearching)
    }

    @Test func `reverting an option during a search restores the cleared results`() async {
        let service = SubtitleService()
        let model = viewModel(service, preferences: SubtitleSearchPreferences(language: "fr"))
        await model.searchIfNeeded()

        service.holdsSearches = true
        model.selectedLanguage = "de"
        let cancelled = Task { await model.searchIfNeeded() }
        while service.heldCount < 1 {
            await Task.yield()
        }
        cancelled.cancel()

        service.holdsSearches = false
        model.selectedLanguage = "fr"
        await model.searchIfNeeded()
        service.release(0)
        await cancelled.value

        #expect(model.results.map(\.id) == ["fr"])
        #expect(model.hasSearched)
        #expect(!model.isSearching)
    }

    @Test func `exact matches rank first, then scores, then provider order`() {
        let ranked = [
            result("none-1"),
            result("low", score: 10),
            result("none-2"),
            result("high", score: 90),
            result("exact", exact: true),
        ].rankedByMatch()

        #expect(ranked.map(\.id) == ["exact", "high", "low", "none-1", "none-2"])
    }

    @Test func `best match needs something that sets it apart`() {
        #expect([result("a", score: 90), result("b", score: 10)].bestMatch?.id == "a")
        #expect([result("a", exact: true), result("b")].bestMatch?.id == "a")
        #expect([result("a", score: 90), result("b")].bestMatch?.id == "a")
        #expect([result("a", score: 90), result("b", score: 90)].bestMatch == nil)
        #expect([result("a"), result("b")].bestMatch == nil)
        #expect([result("a", score: 90)].bestMatch == nil)
    }

    private func result(_ id: String, score: Double? = nil, exact: Bool = false) -> RemoteSubtitleResult {
        RemoteSubtitleResult(
            id: id,
            title: id,
            language: nil,
            codec: "srt",
            providerTitle: nil,
            isExactMatch: exact,
            matchScore: score,
        )
    }
}
