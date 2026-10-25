import SwiftUI

struct SettingsLicensesView: View {
    var body: some View {
        SettingsList {
            Section {
                row(.strimr, isDefault: true)
            }

            Section("settings.licenses.dependencies") {
                ForEach(OpenSourceLicense.dependencies) { license in
                    row(license)
                }
            }
        }
    }

    private func row(_ license: OpenSourceLicense, isDefault: Bool = false) -> some View {
        SettingsLink(title: LocalizedStringKey(license.name)) {
            SettingsLicenseDetailView(license: license)
        } label: {
            HStack(spacing: 20) {
                Text(verbatim: license.name)
                Spacer(minLength: 16)
                Text(verbatim: license.license)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.cardMetadata.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .settingsFocus(license.id, isDefault: isDefault)
    }
}

private struct SettingsLicenseDetailView: View {
    let license: OpenSourceLicense
    private let paragraphs: [String]

    init(license: OpenSourceLicense) {
        self.license = license
        paragraphs = license.text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        SettingsList {
            Section {
                // Each paragraph takes focus so the remote can scroll through the whole text.
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    LicenseParagraph(text: paragraph)
                        .focusable()
                        .settingsFocus("paragraph-\(index)", isDefault: index == 0)
                }
            } header: {
                Text(verbatim: license.url.absoluteString)
            }
        }
    }
}

private struct LicenseParagraph: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.facts.monospaced())
            .foregroundStyle(isFocused ? .textPrimary : .textSecondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isFocused ? Color.surfaceSubtle : .clear,
                in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous),
            )
            .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: isFocused)
    }
}
