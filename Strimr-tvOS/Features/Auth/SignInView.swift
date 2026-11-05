import SwiftUI

struct SignInView: View {
    @State private var viewModel: SignInViewModel

    init(viewModel: SignInViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image("Icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 192, height: 192)
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .accessibilityHidden(true)

                Text("signIn.title")
                    .multilineTextAlignment(.center)
                    .font(.heroTitle)
                    .foregroundStyle(.textPrimary)

                Text("signIn.tv.subtitle")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.textSecondary)
                    .font(.bodyText)
            }

            Group {
                if let pin = viewModel.pin {
                    VStack(spacing: 20) {
                        if let url = plexAuthURL(pin: pin),
                           let qrImage = QRCodeImage.make(url.absoluteString)
                        {
                            qrImage
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 260, height: 260)
                                .clipShape(RoundedRectangle(
                                    cornerRadius: LayoutMetrics.cardCornerRadius,
                                    style: .continuous,
                                ))
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
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.facts)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 720)
            }

            Spacer()
        }
        .padding(48)
        .onAppear { Task { await viewModel.startSignIn() } }
        .onDisappear { viewModel.cancelSignIn() }
    }
}

extension SignInView {
    private func plexAuthURL(pin: PlexCloudPin) -> URL? {
        let base = "https://app.plex.tv/auth#?"
        let fragment =
            "clientID=\(pin.clientIdentifier)" +
            "&context[device][product]=Strimr" +
            "&code=\(pin.code)"

        return URL(string: base + fragment)
    }
}
