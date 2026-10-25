import CoreImage.CIFilterBuiltins
import SwiftUI

struct SettingsAboutView: View {
    var body: some View {
        SettingsList {
            Section {
                HStack {
                    Text("settings.about.version")
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Text(verbatim: AppInfo.version)
                        .foregroundStyle(.textSecondary)
                }
                .padding(.horizontal, 20)

                SettingsLink("settings.licenses.title") {
                    SettingsLicensesView()
                }
                .settingsFocus("licenses", isDefault: true)
            } footer: {
                Text("settings.about.trademarks")
            }

            Section("settings.about.sourceCode") {
                QRCodeLink(url: AppInfo.sourceCodeURL, title: "github.com/wunax/strimr")
            }
        }
    }
}

/// tvOS cannot open links, so a QR code hands them over to a phone.
struct QRCodeLink: View {
    let url: URL
    var title: String?

    var body: some View {
        HStack(spacing: 32) {
            QRCodeView(url: url)
                .frame(width: 200, height: 200)
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(verbatim: title)
                        .font(.rowTitle)
                        .foregroundStyle(.textPrimary)
                }
                Text("settings.about.scanToOpen")
                    .font(.facts)
                    .foregroundStyle(.textSecondary)
            }
        }
    }
}

private struct QRCodeView: View {
    let url: URL

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(12)
                .background(
                    .white,
                    in: RoundedRectangle(cornerRadius: MediaArtworkMetrics.compactCornerRadius, style: .continuous),
                )
        }
    }

    private var image: CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
