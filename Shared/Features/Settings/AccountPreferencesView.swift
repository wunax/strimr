import SwiftUI

@MainActor
struct AccountPreferencesView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        let targets = sessionManager.registry.accountPreferencesTargets()
        Group {
            if targets.isEmpty {
                ContentUnavailableView(
                    "settings.accountPreferences.empty.title",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("settings.accountPreferences.empty.message"),
                )
            } else if targets.count == 1, let target = targets.first {
                AccountPreferencesDetailView(target: target)
                    .id(target.id)
            } else {
                List {
                    Section {
                        ForEach(targets) { target in
                            NavigationLink {
                                AccountPreferencesDetailView(target: target)
                                    .navigationTitle(target.title)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: target.title)
                                    Text(verbatim: target.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text("settings.accountPreferences.pickAccount")
                    }
                }
                .insetListStyle()
            }
        }
        .navigationTitle("settings.accountPreferences.title")
    }
}

@MainActor
private struct AccountPreferencesDetailView: View {
    @State private var viewModel: AccountPreferencesViewModel

    init(target: AccountPreferencesTarget) {
        _viewModel = State(initialValue: AccountPreferencesViewModel(service: target.service))
    }

    var body: some View {
        Group {
            if viewModel.loadFailed {
                ContentUnavailableView {
                    Label("settings.accountPreferences.loadFailed", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("common.actions.retry") {
                        Task { await viewModel.load() }
                    }
                }
            } else if let preferences = viewModel.preferences {
                form(preferences)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await viewModel.load() }
        .alert("settings.accountPreferences.saveFailed", isPresented: $viewModel.saveFailed) {
            Button("common.actions.done", role: .cancel) {}
        }
    }

    private func form(_ preferences: AccountPreferences) -> some View {
        List {
            Section {
                languagePicker(
                    "settings.accountPreferences.audioLanguage",
                    selection: viewModel.audioLanguage,
                    selected: preferences.audioLanguage,
                )
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        "settings.accountPreferences.selectsAudioByLanguage",
                        isOn: viewModel.selectsAudioByLanguage,
                    )
                    Text("settings.accountPreferences.selectsAudioByLanguage.footer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("settings.playback.audio.title")
            }

            Section {
                languagePicker(
                    "settings.accountPreferences.subtitleLanguage",
                    selection: viewModel.subtitleLanguage,
                    selected: preferences.subtitleLanguage,
                )
                Picker("settings.accountPreferences.subtitleMode", selection: viewModel.subtitleMode) {
                    ForEach(viewModel.subtitleModes, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("settings.playback.subtitles.title")
            } footer: {
                Text("settings.accountPreferences.footer")
            }
        }
        .insetListStyle()
    }

    private func languagePicker(
        _ title: LocalizedStringKey,
        selection: Binding<String?>,
        selected: String?,
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(viewModel.languageOptions(selected: selected), id: \.self) { code in
                Text(viewModel.languageTitle(code)).tag(code)
            }
        }
        #if os(iOS)
        .pickerStyle(.navigationLink)
        #endif
    }
}
