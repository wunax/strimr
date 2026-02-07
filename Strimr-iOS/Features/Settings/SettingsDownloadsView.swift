import SwiftUI

@MainActor
struct SettingsDownloadsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        List {
            Section {
                Toggle(
                    "settings.downloads.wifiOnly",
                    isOn: Binding(
                        get: { settingsManager.downloads.wifiOnly },
                        set: { settingsManager.setDownloadWiFiOnly($0) },
                    ),
                )
            } footer: {
                Text("settings.downloads.wifiOnly.footer")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("settings.downloads.title")
    }
}
