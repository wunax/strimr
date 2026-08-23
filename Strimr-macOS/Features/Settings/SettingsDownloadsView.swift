import SwiftUI

@MainActor
struct SettingsDownloadsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        List {
            Section {
                Picker(
                    "settings.downloads.quality",
                    selection: Binding(
                        get: { settingsManager.downloads.qualityPreset },
                        set: { settingsManager.setDownloadQualityPreset($0) },
                    ),
                ) {
                    ForEach(TranscodeQualityPreset.displayOrder) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
            } footer: {
                Text("settings.downloads.quality.footer")
            }

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
        .navigationTitle("settings.downloads.title")
    }
}
