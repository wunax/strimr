import SwiftUI

struct SettingsPrivacyView: View {
    @State private var sendsErrorReports = ErrorReporter.isEnabled

    var body: some View {
        SettingsList {
            Section {
                Toggle("settings.privacy.errorReports", isOn: $sendsErrorReports)
                    .settingsFocus("settings.privacy.errorReports", isDefault: true)
            } footer: {
                Text("settings.privacy.errorReports.footer")
            }

            Section("settings.privacy.policy") {
                QRCodeLink(url: AppInfo.privacyPolicyURL)
            }
        }
        .onChange(of: sendsErrorReports) { _, enabled in
            ErrorReporter.setEnabled(enabled)
        }
    }
}
