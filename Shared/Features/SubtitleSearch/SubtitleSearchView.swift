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
    struct SearchOptions: Hashable {
        let language: String
        let hearingImpaired: Bool
        let forced: Bool
    }

    var selectedLanguage: String
    var hearingImpaired: Bool
    var forced: Bool
    var title = ""
    var results: [RemoteSubtitleResult] = []
    var isSearching = false
    var attachingResultID: String?
    var errorMessage: String?
    var hasSearched = false

    let languages = SubtitleLanguageOption.all

    private let itemID: String
    private let services: MediaServices
    /// The device language until the account's subtitle language is known.
    private var defaultLanguage: String
    private var hasResolvedAccountLanguage = false
    private let onPreferencesChange: (SubtitleSearchPreferences) -> Void
    private var preferences: SubtitleSearchPreferences
    private var completedOptions: SearchOptions?
    private var searchGeneration = 0

    init(
        itemID: String,
        services: MediaServices,
        preferences: SubtitleSearchPreferences = SubtitleSearchPreferences(),
        onPreferencesChange: @escaping (SubtitleSearchPreferences) -> Void = { _ in },
    ) {
        self.itemID = itemID
        self.services = services
        self.preferences = preferences
        self.onPreferencesChange = onPreferencesChange
        let preferred = Locale.preferredLanguages.first ?? "en"
        let deviceLanguage = Locale.Language(identifier: preferred).languageCode?.identifier ?? "en"
        defaultLanguage = deviceLanguage
        selectedLanguage = preferences.language ?? deviceLanguage
        // Servers without these options hide their toggles, so a saved value could not be turned off there.
        let supportsAdvancedOptions = services.detail.supportsAdvancedSubtitleSearch
        hearingImpaired = supportsAdvancedOptions && preferences.hearingImpaired
        forced = supportsAdvancedOptions && preferences.forced
    }

    var searchOptions: SearchOptions {
        SearchOptions(language: selectedLanguage, hearingImpaired: hearingImpaired, forced: forced)
    }

    var bestMatchID: String? {
        results.bestMatch?.id
    }

    /// Reappearing after the language list was pushed must not repeat a search that already completed.
    func searchIfNeeded() async {
        await resolveAccountLanguageIfNeeded()
        guard !Task.isCancelled, completedOptions != searchOptions || !hasSearched else { return }
        await search()
    }

    func search() async {
        guard attachingResultID == nil else { return }
        let options = searchOptions
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        errorMessage = nil
        if completedOptions != options {
            results = []
            hasSearched = false
        }
        rememberPreferences()
        defer {
            if generation == searchGeneration {
                isSearching = false
            }
        }

        do {
            let values = try await services.detail.searchSubtitles(
                itemID: itemID,
                language: options.language,
                hearingImpaired: options.hearingImpaired,
                forced: options.forced,
                title: title,
            )
            guard generation == searchGeneration, !Task.isCancelled else { return }
            results = values.rankedByMatch()
            hasSearched = true
            completedOptions = options
        } catch {
            guard generation == searchGeneration, !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            errorMessage = error.localizedDescription
        }
    }

    private func resolveAccountLanguageIfNeeded() async {
        guard !hasResolvedAccountLanguage else { return }
        guard let service = services.accountPreferences else {
            hasResolvedAccountLanguage = true
            return
        }
        do {
            let account = try await service.load()
            hasResolvedAccountLanguage = true
            guard let language = AccountLanguageCode.normalized(account.subtitleLanguage) else { return }
            // A language picked while the account was loading wins over it.
            if preferences.language == nil, selectedLanguage == defaultLanguage {
                selectedLanguage = language
            }
            defaultLanguage = language
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            hasResolvedAccountLanguage = true
            ErrorReporter.capture(error)
        }
    }

    private func rememberPreferences() {
        var updated = preferences
        if selectedLanguage != preferences.language ?? defaultLanguage {
            // Picking the default again drops the saved language, so the sheet follows later account changes.
            updated.language = selectedLanguage == defaultLanguage ? nil : selectedLanguage
        }
        if services.detail.supportsAdvancedSubtitleSearch {
            updated.hearingImpaired = hearingImpaired
            updated.forced = forced
        }
        guard updated != preferences else { return }
        preferences = updated
        onPreferencesChange(updated)
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
    @Environment(SettingsManager.self) private var settingsManager
    let itemID: String
    let titlePlaceholder: String
    let services: MediaServices
    let onAttached: (RemoteSubtitleResult) async -> Void

    var body: some View {
        SubtitleSearchContentView(
            itemID: itemID,
            titlePlaceholder: titlePlaceholder,
            services: services,
            preferences: settingsManager.playback.subtitleSearch,
            onPreferencesChange: settingsManager.setSubtitleSearchPreferences(_:),
            onAttached: onAttached,
        )
    }
}

private struct SubtitleSearchContentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SubtitleSearchViewModel
    let titlePlaceholder: String
    let onAttached: (RemoteSubtitleResult) async -> Void
    private let showsAdvancedOptions: Bool

    init(
        itemID: String,
        titlePlaceholder: String,
        services: MediaServices,
        preferences: SubtitleSearchPreferences,
        onPreferencesChange: @escaping (SubtitleSearchPreferences) -> Void,
        onAttached: @escaping (RemoteSubtitleResult) async -> Void,
    ) {
        _viewModel = State(initialValue: SubtitleSearchViewModel(
            itemID: itemID,
            services: services,
            preferences: preferences,
            onPreferencesChange: onPreferencesChange,
        ))
        self.titlePlaceholder = titlePlaceholder
        self.onAttached = onAttached
        showsAdvancedOptions = services.detail.supportsAdvancedSubtitleSearch
    }

    var body: some View {
        TaskModalNavigationView {
            subtitleSearchContent
                .task(id: viewModel.searchOptions) {
                    await viewModel.searchIfNeeded()
                }
                .taskModalTitle("subtitles.search.title")
            #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.actions.cancel") { dismiss() }
                    }
                }
            #endif
        }
    }

    private var subtitleSearchContent: some View {
        #if os(tvOS)
            HStack(alignment: .top, spacing: 40) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text(titlePlaceholder)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        searchOptions
                    }
                    .padding(24)
                }
                .frame(width: 500)
                .focusSection()
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if viewModel.isSearching {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 160)
                        }
                        resultsSection
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .focusSection()
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
        .disabled(viewModel.attachingResultID != nil)
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
                                if viewModel.bestMatchID == result.id {
                                    Label("subtitles.search.bestMatch", systemImage: "star.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
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
    func centeredSubtitleSearchAction() -> some View {
        #if os(tvOS)
            frame(maxWidth: .infinity, alignment: .center)
        #else
            self
        #endif
    }
}
