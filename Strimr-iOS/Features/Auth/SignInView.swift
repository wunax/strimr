import SwiftUI

struct SignInView: View {
    @State private var viewModel: SignInViewModel

    init(viewModel: SignInViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image("Icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .accessibilityHidden(true)

                Text("signIn.title")
                    .multilineTextAlignment(.center)
                    .font(.largeTitle.bold())

                Text("signIn.subtitle")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.startSignIn() }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(viewModel.isAuthenticating ? "signIn.button.waiting" : "signIn.button.continue")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .controlSize(.large)
            .tint(.brandPrimary)
            .frame(maxWidth: 520)
            .disabled(viewModel.isAuthenticating)

            if viewModel.isAuthenticating {
                Button("signIn.button.cancel") { viewModel.cancelSignIn() }
                    .padding(.top, 4)
            }

            if let errorMessage = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            }

            Spacer()
        }
        .padding(24)
        .onDisappear { viewModel.cancelSignIn() }
    }
}
