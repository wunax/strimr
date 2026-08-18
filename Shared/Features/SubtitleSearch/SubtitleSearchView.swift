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
    var results: [RemoteSubtitleResult] = []
    var isSearching = false
    var attachingResultID: String?
    var errorMessage: String?
    var hasSearched = false

    let languages = SubtitleLanguageOption.all

    private let itemID: String
    private let services: MediaServices

    init(itemID: String, services: MediaServices) {
        self.itemID = itemID
        self.services = services
        let preferred = Locale.preferredLanguages.first ?? "en"
        selectedLanguage = Locale.Language(identifier: preferred).languageCode?.identifier ?? "en"
    }

    func search() async {
        guard !isSearching, attachingResultID == nil else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            results = try await services.detail.searchSubtitles(
                itemID: itemID,
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

    func attach(_ result: RemoteSubtitleResult) async -> Bool {
        guard attachingResultID == nil else { return false }
        attachingResultID = result.id
        errorMessage = nil
        defer { attachingResultID = nil }

        do {
            try await services.detail.installSubtitle(itemID: itemID, result: result)
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
    let onAttached: (RemoteSubtitleResult) async -> Void
    private let showsAdvancedOptions: Bool

    init(
        itemID: String,
        titlePlaceholder: String,
        services: MediaServices,
        onAttached: @escaping (RemoteSubtitleResult) async -> Void,
    ) {
        _viewModel = State(initialValue: SubtitleSearchViewModel(itemID: itemID, services: services))
        self.titlePlaceholder = titlePlaceholder
        self.onAttached = onAttached
        showsAdvancedOptions = services.detail.supportsAdvancedSubtitleSearch
    }

    var body: some View {
        NavigationStack {
            subtitleSearchContent
                .navigationTitle("subtitles.search.title")
            #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.actions.cancel") { dismiss() }
                    }
                }
            #endif
        }
    }

    @ViewBuilder
    private var subtitleSearchContent: some View {
        #if os(tvOS)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    searchOptions
                    resultsSection
                }
                .padding(.horizontal, 42)
                .padding(.vertical, 20)
            }
        #else
            List {
                searchOptions
                resultsSection
            }
        #endif
    }

    private var searchOptions: some View {
        Section {
            #if os(tvOS)
                Picker("subtitles.search.language", selection: $viewModel.selectedLanguage) {
                    ForEach(viewModel.languages) { language in
                        Text(language.name)
                            .tag(language.code)
                    }
                }
                .pickerStyle(.menu)
            #else
                NavigationLink {
                    SubtitleLanguageSelectionView(
                        languages: viewModel.languages,
                        selection: $viewModel.selectedLanguage,
                    )
                } label: {
                    LabeledContent("subtitles.search.language") {
                        Text(selectedLanguageName)
                            .foregroundStyle(.secondary)
                    }
                }
            #endif

            if showsAdvancedOptions {
                Toggle("subtitles.search.hearingImpaired", isOn: $viewModel.hearingImpaired)
                Toggle("subtitles.search.forced", isOn: $viewModel.forced)
                TextField(
                    "subtitles.search.releaseTitle",
                    text: $viewModel.title,
                    prompt: Text(titlePlaceholder),
                )
            }

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
            .tint(.secondary)
            .centeredSubtitleSearchAction()
        }
    }

    private var selectedLanguageName: String {
        viewModel.languages.first { $0.code == viewModel.selectedLanguage }?.name
            ?? viewModel.selectedLanguage
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
                                Text(result.title)
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

    private func resultDetail(_ result: RemoteSubtitleResult) -> String {
        [result.language, result.codec.uppercased(), result.providerTitle]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private func attach(_ result: RemoteSubtitleResult) {
        Task {
            guard await viewModel.attach(result) else { return }
            dismiss()
            await onAttached(result)
        }
    }
}

#if !os(tvOS)
    private struct SubtitleLanguageSelectionView: View {
        @Environment(\.dismiss) private var dismiss
        let languages: [SubtitleLanguageOption]
        @Binding var selection: String
        @State private var searchText = ""

        private var filteredLanguages: [SubtitleLanguageOption] {
            guard !searchText.isEmpty else { return languages }
            return languages.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.code.localizedCaseInsensitiveContains(searchText)
            }
        }

        var body: some View {
            List(filteredLanguages) { language in
                Button {
                    selection = language.code
                    dismiss()
                } label: {
                    HStack {
                        Text(language.name)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(language.code.uppercased())
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        if selection == language.code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
            .navigationTitle("subtitles.search.language")
            .searchable(text: $searchText, prompt: "subtitles.search.language.search")
        }
    }
#endif

private extension View {
    @ViewBuilder
    func centeredSubtitleSearchAction() -> some View {
        #if os(tvOS)
            frame(maxWidth: .infinity, alignment: .center)
        #else
            self
        #endif
    }
}
