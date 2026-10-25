import SwiftUI

struct SettingsAboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("settings.about.version") {
                    Text(verbatim: AppInfo.version)
                        .textSelection(.enabled)
                }
            }

            Section {
                Link(destination: AppInfo.sourceCodeURL) {
                    Label("settings.about.sourceCode", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: AppInfo.issuesURL) {
                    Label("settings.about.reportIssue", systemImage: "ladybug")
                }
                Link(destination: AppInfo.testFlightURL) {
                    Label("settings.about.joinBeta", systemImage: "testtube.2")
                }
                Link(destination: AppInfo.reviewURL) {
                    Label("settings.about.rate", systemImage: "star")
                }
            }
            .foregroundStyle(.secondary)

            Section {
                NavigationLink("settings.licenses.title") {
                    SettingsLicensesView()
                }
            } footer: {
                Text("settings.about.trademarks")
            }
        }
        .insetListStyle()
        .navigationTitle("settings.about.title")
    }
}
