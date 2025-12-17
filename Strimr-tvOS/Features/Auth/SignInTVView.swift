import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct SignInTVView: View {
    @State private var viewModel: SignInTVViewModel

    private let ciContext = CIContext()

    init(viewModel: SignInTVViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("signIn.title")
                    .multilineTextAlignment(.center)
                    .font(.largeTitle.bold())

                Text("signIn.tv.subtitle")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
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

                        Text("signIn.tv.codeLabel \(pin.code)")
                            .font(.title2.monospacedDigit())
                            .fontWeight(.bold)
                    }
                } else if viewModel.isAuthenticating {
                    ProgressView("signIn.button.waiting")
                        .progressViewStyle(.circular)
                }
            }

            Spacer()
        }
        .padding(48)
        .onAppear { Task { await viewModel.startSignIn() } }
        .onDisappear { viewModel.cancelSignIn() }
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
