import SwiftUI

struct SettingsLicensesView: View {
    var body: some View {
        List {
            Section {
                row(.strimr)
            }

            Section("settings.licenses.dependencies") {
                ForEach(OpenSourceLicense.dependencies) { license in
                    row(license)
                }
            }
        }
        .insetListStyle()
        .navigationTitle("settings.licenses.title")
    }

    private func row(_ license: OpenSourceLicense) -> some View {
        NavigationLink {
            SettingsLicenseDetailView(license: license)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: license.name)
                Text(verbatim: license.license)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsLicenseDetailView: View {
    let license: OpenSourceLicense
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Link(destination: license.url) {
                    Label("settings.licenses.source", systemImage: "arrow.up.right.square")
                }
                .foregroundStyle(.secondary)
                Text(verbatim: text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LayoutMetrics.pageMargin)
        }
        .navigationTitle(Text(verbatim: license.name))
        .task {
            text = license.text
        }
    }
}
