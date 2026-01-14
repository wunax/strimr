import SwiftUI

struct SignInView: View {
    @State private var viewModel: SignInViewModel
    @State private var isShowingErrorDetails = false

    init(viewModel: SignInViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(.icon)
                    .resizable()
                    .frame(width: 128, height: 128)

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
                HStack {
                    if viewModel.isAuthenticating { ProgressView().tint(.white) }
                    Text(viewModel.isAuthenticating ? "signIn.button.waiting" : "signIn.button.continue")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.brandPrimary)
                .foregroundStyle(.brandPrimaryForeground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(viewModel.isAuthenticating)

            if viewModel.isAuthenticating {
                Button("signIn.button.cancel") { viewModel.cancelSignIn() }
                    .padding(.top, 4)
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
                                Text(isShowingErrorDetails ? "common.actions.hideDetails" :
                                    "common.actions.showDetails")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            },
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            }

            Spacer()
        }
        .padding(24)
        .onChange(of: viewModel.errorDetails) { _, _ in
            isShowingErrorDetails = false
        }
    }
}
