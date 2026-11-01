import Foundation
import Observation

@MainActor
@Observable
final class MatchSearchViewModel: Identifiable {
    struct Failure: Identifiable {
        let id = UUID()
        let message: String
    }

    let item: MediaItem
    var title: String
    var year: String
    private(set) var results: [MatchCandidate] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false
    private(set) var errorMessage: String?
    /// The result being applied, which shows a progress on its row.
    private(set) var applyingCandidateID: String?
    var failure: Failure?
    /// Set once the server accepted a new match; the screen then closes.
    private(set) var appliedCandidate: MatchCandidate?

    @ObservationIgnored private let searchHandler: (String, Int?) async throws -> [MatchCandidate]
    @ObservationIgnored private let applyHandler: (MatchCandidate) async throws -> Void
    @ObservationIgnored private let onApplied: (String) -> Void

    init(
        item: MediaItem,
        search: @escaping (String, Int?) async throws -> [MatchCandidate],
        apply: @escaping (MatchCandidate) async throws -> Void,
        onApplied: @escaping (String) -> Void,
    ) {
        self.item = item
        title = item.title
        year = item.year.map(String.init) ?? ""
        searchHandler = search
        applyHandler = apply
        self.onApplied = onApplied
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A year that is not a number is left out of the search rather than refused.
    var searchYear: Int? {
        Int(year.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var canSearch: Bool {
        !trimmedTitle.isEmpty && !isSearching && applyingCandidateID == nil
    }

    func search() async {
        guard canSearch else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            let results = try await searchHandler(trimmedTitle, searchYear)
            guard !Task.isCancelled else { return }
            self.results = results
            hasSearched = true
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            errorMessage = message(for: error)
        }
    }

    func apply(_ candidate: MatchCandidate) async {
        guard applyingCandidateID == nil, !isSearching else { return }
        applyingCandidateID = candidate.id
        defer { applyingCandidateID = nil }
        do {
            try await applyHandler(candidate)
            onApplied(item.id)
            appliedCandidate = candidate
        } catch {
            guard !error.isCancellation else { return }
            failure = Failure(message: message(for: error))
        }
    }

    /// Captures unexpected failures; a refusal is the server's answer to a right lost meanwhile.
    private func message(for error: Error) -> String {
        guard !error.isManagementRefusal else { return String(localized: "media.manage.error.forbidden") }
        ErrorReporter.capture(error)
        return error.localizedDescription
    }
}
