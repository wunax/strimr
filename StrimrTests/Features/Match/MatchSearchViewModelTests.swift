import Foundation
@testable import Strimr
import Testing

@MainActor
struct MatchSearchViewModelTests {
    private struct Failure: LocalizedError {
        var errorDescription: String? {
            "Agent unavailable"
        }
    }

    private final class Calls {
        var searches: [(String, Int?)] = []
        var applied: [String] = []
        var changed: [String] = []
    }

    private let candidate = MatchCandidate(
        id: "plex://movie/1",
        title: "Sample Movie",
        year: 2010,
        posterURL: nil,
        provider: "plex",
        isCurrent: false,
        payload: .plex(guid: "plex://movie/1"),
    )

    private func makeViewModel(calls: Calls, error: Error? = nil) -> MatchSearchViewModel {
        let item = MediaItem.make(
            id: "item",
            server: ServerIdentity(provider: .plex, id: "server"),
            title: "Sample Movie",
            year: 2010,
        )
        return MatchSearchViewModel(
            item: item,
            search: { [candidate] title, year in
                calls.searches.append((title, year))
                if let error {
                    throw error
                }
                return [candidate]
            },
            apply: { candidate in
                calls.applied.append(candidate.id)
                if let error {
                    throw error
                }
            },
        ) { calls.changed.append($0) }
    }

    @Test func `search starts from the item's title and year`() async {
        let calls = Calls()
        let viewModel = makeViewModel(calls: calls)

        await viewModel.search()

        #expect(calls.searches.map(\.0) == ["Sample Movie"])
        #expect(calls.searches.map(\.1) == [2010])
        #expect(viewModel.results == [candidate])
        #expect(viewModel.hasSearched)
    }

    @Test func `a year that is not a number is left out and the title is trimmed`() async {
        let calls = Calls()
        let viewModel = makeViewModel(calls: calls)
        viewModel.title = "  Other Title "
        viewModel.year = "20x"

        await viewModel.search()

        #expect(calls.searches.map(\.0) == ["Other Title"])
        #expect(calls.searches.map(\.1) == [nil])
    }

    @Test func `an empty title is not searched`() async {
        let calls = Calls()
        let viewModel = makeViewModel(calls: calls)
        viewModel.title = "   "

        await viewModel.search()

        #expect(calls.searches.isEmpty)
        #expect(!viewModel.canSearch)
    }

    @Test func `applying a match notifies the change and closes the search`() async {
        let calls = Calls()
        let viewModel = makeViewModel(calls: calls)

        await viewModel.apply(candidate)

        #expect(calls.applied == [candidate.id])
        #expect(calls.changed == ["item"])
        #expect(viewModel.appliedCandidate == candidate)
        #expect(viewModel.applyingCandidateID == nil)
    }

    @Test func `a refused match explains the lost right and keeps the search open`() async {
        let calls = Calls()
        let viewModel = makeViewModel(calls: calls, error: PlexAPIError.requestFailed(statusCode: 403))

        await viewModel.apply(candidate)

        #expect(viewModel.failure?.message == String(localized: "media.manage.error.forbidden"))
        #expect(viewModel.appliedCandidate == nil)
        #expect(calls.changed.isEmpty)
    }

    @Test func `a failed search shows the server message`() async {
        let viewModel = makeViewModel(calls: Calls(), error: Failure())

        await viewModel.search()

        #expect(viewModel.errorMessage == "Agent unavailable")
        #expect(!viewModel.hasSearched)
    }
}
