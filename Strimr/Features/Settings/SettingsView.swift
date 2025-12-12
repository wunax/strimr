import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    private var autoPlayNextBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.playback.autoPlayNextEpisode },
            set: { settingsManager.setAutoPlayNextEpisode($0) }
        )
    }

    var body: some View {
        List {
            Section("Playback") {
                Toggle("Play next episode automatically", isOn: autoPlayNextBinding)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(SettingsManager())
    }
}
