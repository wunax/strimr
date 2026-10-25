import SwiftUI

struct SettingsPrivacyView: View {
    @State private var sendsErrorReports = ErrorReporter.isEnabled

    var body: some View {
        List {
            Section {
                Toggle("settings.privacy.errorReports", isOn: $sendsErrorReports)
            } footer: {
                Text("settings.privacy.errorReports.footer")
            }

            Section {
                Link(destination: AppInfo.privacyPolicyURL) {
                    Label("settings.privacy.policy", systemImage: "doc.text")
                }
                .foregroundStyle(.secondary)
            }
        }
        .insetListStyle()
        .navigationTitle("settings.privacy.title")
        .onChange(of: sendsErrorReports) { _, enabled in
            ErrorReporter.setEnabled(enabled)
        }
    }
}
