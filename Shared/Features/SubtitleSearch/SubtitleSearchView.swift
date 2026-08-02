import Foundation
import Observation
import SwiftUI

struct SubtitleLanguageOption: Hashable, Identifiable {
    let code: String
    let name: String

    var id: String {
        code
    }

    static let all: [SubtitleLanguageOption] = Locale.LanguageCode.isoLanguageCodes
        .map(\.identifier)
        .reduce(into: Set<String>()) { $0.insert($1) }
        .map { code in
            SubtitleLanguageOption(
                code: code,
                name: Locale.current.localizedString(forLanguageCode: code) ?? code,
            )
        }
        .sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.code < $1.code : comparison == .orderedAscending
        }
}

@MainActor
@Observable
final class SubtitleSearchViewModel {
    var selectedLanguage: String
    var hearingImpaired = false
    var forced = false
    var title = ""
    var results: [PlexSubtitleSearchResult] = []
    var isSearching = false
    var attachingResultID: Int?
    var errorMessage: String?
    var hasSearched = false

    let languages = SubtitleLanguageOption.all

    private let ratingKey: String
    private let repository: SubtitleRepository

    init(ratingKey: String, context: PlexAPIContext) {
        self.ratingKey = ratingKey
        repository = SubtitleRepository(context: context)
        let preferred = Locale.preferredLanguages.first ?? "en"
        selectedLanguage = Locale.Language(identifier: preferred).languageCode?.identifier ?? "en"
    }

    func search() async {
        guard !isSearching, attachingResultID == nil else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            results = try await repository.search(
                ratingKey: ratingKey,
                language: selectedLanguage,
                hearingImpaired: hearingImpaired,
                forced: forced,
                title: title,
            )
            hasSearched = true
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            errorMessage = error.localizedDescription
        }
    }

    func attach(_ result: PlexSubtitleSearchResult) async -> Bool {
        guard attachingResultID == nil else { return false }
        attachingResultID = result.id
        errorMessage = nil
        defer { attachingResultID = nil }

        do {
            try await repository.attach(
                ratingKey: ratingKey,
                result: result,
                searchedLanguage: selectedLanguage,
                searchedHearingImpaired: hearingImpaired,
                searchedForced: forced,
            )
            return true
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return false }
            ErrorReporter.capture(error)
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct SubtitleSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SubtitleSearchViewModel
    let titlePlaceholder: String
    let onAttached: (PlexSubtitleSearchResult) async -> Void

    init(
        ratingKey: String,
        titlePlaceholder: String,
        context: PlexAPIContext,
        onAttached: @escaping (PlexSubtitleSearchResult) async -> Void,
    ) {
        _viewModel = State(initialValue: SubtitleSearchViewModel(ratingKey: ratingKey, context: context))
        self.titlePlaceholder = titlePlaceholder
        self.onAttached = onAttached
    }

    var body: some View {
        NavigationStack {
            List {
                searchOptions
                resultsSection
            }
            .navigationTitle("subtitles.search.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.actions.cancel") { dismiss() }
                }
            }
        }
    }

    private var searchOptions: some View {
        Section {
            NavigationLink {
                SubtitleLanguageSelectionView(
                    languages: viewModel.languages,
                    selection: $viewModel.selectedLanguage,
                )
            } label: {
                LabeledContent("subtitles.search.language", value: selectedLanguageName)
            }

            Toggle("subtitles.search.hearingImpaired", isOn: $viewModel.hearingImpaired)
            Toggle("subtitles.search.forced", isOn: $viewModel.forced)
            TextField(
                "subtitles.search.releaseTitle",
                text: $viewModel.title,
                prompt: Text(titlePlaceholder),
            )

            Button {
                Task { await viewModel.search() }
            } label: {
                if viewModel.isSearching {
                    ProgressView()
                } else {
                    Label("subtitles.search.action", systemImage: "magnifyingglass")
                }
            }
            .disabled(viewModel.isSearching || viewModel.attachingResultID != nil)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Section {
                ContentUnavailableView(
                    "subtitles.search.error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage),
                )
            }
        } else if viewModel.hasSearched, viewModel.results.isEmpty {
            Section {
                ContentUnavailableView(
                    "subtitles.search.empty",
                    systemImage: "captions.bubble",
                    description: Text("subtitles.search.empty.description"),
                )
            }
        } else if !viewModel.results.isEmpty {
            Section("subtitles.search.results") {
                ForEach(viewModel.results) { result in
                    Button {
                        attach(result)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title ?? result.extendedDisplayTitle ?? result.displayTitle)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Text(resultDetail(result))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            if viewModel.attachingResultID == result.id {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.attachingResultID != nil)
                }
            }
        }
    }

    private var selectedLanguageName: String {
        viewModel.languages.first { $0.code == viewModel.selectedLanguage }?.name
            ?? viewModel.selectedLanguage
    }

    private func resultDetail(_ result: PlexSubtitleSearchResult) -> String {
        [result.language, result.codec.uppercased(), result.providerTitle]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private func attach(_ result: PlexSubtitleSearchResult) {
        Task {
            guard await viewModel.attach(result) else { return }
            dismiss()
            await onAttached(result)
        }
    }
}

private struct SubtitleLanguageSelectionView: View {
    let languages: [SubtitleLanguageOption]
    @Binding var selection: String
    @State private var searchText = ""

    var body: some View {
        List(filteredLanguages) { language in
            Button {
                selection = language.code
            } label: {
                HStack {
                    Text(language.name)
                    Spacer()
                    Text(language.code)
                        .foregroundStyle(.secondary)
                    if selection == language.code {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("subtitles.search.language")
        .searchable(text: $searchText, prompt: "subtitles.search.language.search")
    }

    private var filteredLanguages: [SubtitleLanguageOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return languages }
        return languages.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.code.localizedCaseInsensitiveContains(query)
        }
    }
}
