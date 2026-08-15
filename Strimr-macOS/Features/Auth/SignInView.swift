import SwiftUI

struct SignInView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var viewModel: SignInViewModel

    init(viewModel: SignInViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("plex_logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240, maxHeight: 112)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("signIn.title")
                    .font(.largeTitle.bold())
                Text("signIn.subtitle")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.startSignIn() }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isAuthenticating {
                        ProgressView().controlSize(.small)
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
                Button("signIn.button.cancel") {
                    viewModel.cancelSignIn()
                }
                .buttonStyle(.link)
            }

            Button {
                returnToProviderSelection()
            } label: {
                Label("provider.change", systemImage: "chevron.left")
            }
            .buttonStyle(.link)

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { viewModel.cancelSignIn() }
    }

    private func returnToProviderSelection() {
        viewModel.cancelSignIn()
        Task { await sessionManager.requestProviderSelection() }
    }
}
