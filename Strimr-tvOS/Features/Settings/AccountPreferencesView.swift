import SwiftUI

@MainActor
struct AccountPreferencesView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsNavigation.self) private var navigation

    private func viewModel(for target: AccountPreferencesTarget) -> AccountPreferencesViewModel {
        navigation.accountPreferencesViewModel(for: target, generation: sessionManager.registry.generation)
    }

    var body: some View {
        let targets = sessionManager.registry.accountPreferencesTargets()
        if targets.isEmpty {
            SettingsList {
                Section {
                    Text("settings.accountPreferences.empty.message")
                        .font(.bodyText)
                        .foregroundStyle(.textSecondary)
                } header: {
                    Text("settings.accountPreferences.empty.title")
                }
            }
        } else if targets.count == 1, let target = targets.first {
            AccountPreferencesDetailView(viewModel: viewModel(for: target))
                .id(target.id)
        } else {
            SettingsList {
                Section {
                    ForEach(targets) { target in
                        SettingsLink(title: LocalizedStringKey(target.title)) {
                            AccountPreferencesDetailView(viewModel: viewModel(for: target))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: target.title)
                                Text(verbatim: target.subtitle)
                                    .font(.facts)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .settingsFocus(target.id, isDefault: target.id == targets.first?.id)
                    }
                } footer: {
                    Text("settings.accountPreferences.pickAccount")
                }
            }
        }
    }
}

@MainActor
private struct AccountPreferencesDetailView: View {
    @Bindable var viewModel: AccountPreferencesViewModel

    var body: some View {
        SettingsList {
            if viewModel.loadFailed {
                Section {
                    Button("common.actions.retry") {
                        Task { await viewModel.load() }
                    }
                    .settingsFocus("settings.accountPreferences.retry", isDefault: true)
                } header: {
                    Text("settings.accountPreferences.loadFailed")
                }
            } else if let preferences = viewModel.preferences {
                audioSection(preferences)
                subtitlesSection(preferences)
            } else {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .task { await viewModel.load() }
        .alert("settings.accountPreferences.saveFailed", isPresented: $viewModel.saveFailed) {
            Button("common.actions.done", role: .cancel) {}
        }
    }

    private func audioSection(_ preferences: AccountPreferences) -> some View {
        Section {
            SettingsPicker(
                "settings.accountPreferences.audioLanguage",
                selection: viewModel.audioLanguage,
                options: viewModel.languageOptions(selected: preferences.audioLanguage),
            ) { code in
                Text(viewModel.languageTitle(code))
            }
            .settingsFocus("settings.accountPreferences.audioLanguage", isDefault: true)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    "settings.accountPreferences.selectsAudioByLanguage",
                    isOn: viewModel.selectsAudioByLanguage,
                )
                .settingsFocus("settings.accountPreferences.selectsAudioByLanguage")
                Text("settings.accountPreferences.selectsAudioByLanguage.footer")
                    .font(.facts)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("settings.playback.audio.title")
        }
    }

    private func subtitlesSection(_ preferences: AccountPreferences) -> some View {
        Section {
            SettingsPicker(
                "settings.accountPreferences.subtitleLanguage",
                selection: viewModel.subtitleLanguage,
                options: viewModel.languageOptions(selected: preferences.subtitleLanguage),
            ) { code in
                Text(viewModel.languageTitle(code))
            }
            .settingsFocus("settings.accountPreferences.subtitleLanguage")

            SettingsPicker(
                "settings.accountPreferences.subtitleMode",
                selection: viewModel.subtitleMode,
                options: viewModel.subtitleModes,
            ) { mode in
                Text(mode.title)
            }
            .settingsFocus("settings.accountPreferences.subtitleMode")
        } header: {
            Text("settings.playback.subtitles.title")
        } footer: {
            Text("settings.accountPreferences.footer")
        }
    }
}
