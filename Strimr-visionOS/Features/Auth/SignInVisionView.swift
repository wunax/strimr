import SwiftUI

struct SignInVisionView: View {
    @State private var viewModel: SignInViewModel

    init(viewModel: SignInViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(.icon)
                    .resizable()
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))

                Text("signIn.title")
                    .multilineTextAlignment(.center)
                    .font(.extraLargeTitle)

                Text("signIn.subtitle")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }

            Button {
                Task { await viewModel.startSignIn() }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isAuthenticating { ProgressView().tint(.white) }
                    Text(viewModel.isAuthenticating ? "signIn.button.waiting" : "signIn.button.continue")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 280)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .tint(.brandPrimary)
            .disabled(viewModel.isAuthenticating)

            if viewModel.isAuthenticating {
                Button("signIn.button.cancel") { viewModel.cancelSignIn() }
                    .padding(.top, 4)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }

            Spacer()
        }
        .padding(40)
    }
}
