import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct SignInTVView: View {
    @State private var viewModel: SignInTVViewModel
    @State private var isShowingErrorDetails = false

    private let ciContext = CIContext()

    init(viewModel: SignInTVViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 192, height: 192)

                Text("signIn.title")
                    .multilineTextAlignment(.center)
                    .font(.largeTitle.bold())

                Text("signIn.tv.subtitle")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }

            Group {
                if let pin = viewModel.pin {
                    VStack(spacing: 20) {
                        if let url = plexAuthURL(pin: pin),
                           let qrImage = qrImage(from: url.absoluteString)
                        {
                            Image(uiImage: qrImage)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 260, height: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            ProgressView("signIn.button.waiting")
                                .progressViewStyle(.circular)
                        }
                    }
                } else if viewModel.isAuthenticating {
                    ProgressView("signIn.button.waiting")
                        .progressViewStyle(.circular)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .foregroundStyle(.red)

                    if let errorDetails = viewModel.errorDetails {
                        DisclosureGroup(
                            isExpanded: $isShowingErrorDetails,
                            content: {
                                Text(errorDetails)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            },
                            label: {
                                Text(isShowingErrorDetails ? "common.actions.hideDetails" : "common.actions.showDetails")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            },
                        )
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.top, 16)
            }

            Spacer()
        }
        .padding(48)
        .onAppear { Task { await viewModel.startSignIn() } }
        .onDisappear { viewModel.cancelSignIn() }
        .onChange(of: viewModel.errorDetails) { _, _ in
            isShowingErrorDetails = false
        }
    }
}

extension SignInTVView {
    private func qrImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .ascii) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))

        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func plexAuthURL(pin: PlexCloudPin) -> URL? {
        let base = "https://app.plex.tv/auth#?"
        let fragment =
            "clientID=\(pin.clientIdentifier)" +
            "&context[device][product]=Strimr" +
            "&code=\(pin.code)"

        return URL(string: base + fragment)
    }
}
