import SwiftUI

struct WatchTogetherVisionView: View {
    @Environment(WatchTogetherViewModel.self) private var viewModel
    @Environment(PlexAPIContext.self) private var plexApiContext
    @State private var isShowingLeaveAlert = false

    private var isConnecting: Bool {
        viewModel.connectionState == .connecting
    }

    var body: some View {
        Group {
            if viewModel.isInSession {
                lobbyView
            } else {
                entryView
            }
        }
        .navigationTitle("watchTogether.title")
        .alert("watchTogether.leave.title", isPresented: $isShowingLeaveAlert) {
            Button("watchTogether.leave.confirm", role: .destructive) {
                viewModel.leaveSession(endForAll: false)
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("watchTogether.leave.message")
        }
    }

    private var entryView: some View {
        HStack(spacing: 32) {
            panelView(title: "watchTogether.create.title") {
                VStack(spacing: 16) {
                    Text("watchTogether.create.description")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        viewModel.createSession()
                    } label: {
                        Label("watchTogether.create.button", systemImage: "plus.circle.fill")
                            .frame(minWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .disabled(isConnecting)

                    if isConnecting {
                        ProgressView()
                    }
                }
            }

            panelView(title: "watchTogether.join.title") {
                VStack(spacing: 16) {
                    Text("watchTogether.join.description")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    TextField("watchTogether.join.codePlaceholder", text: Binding(
                        get: { viewModel.joinCode },
                        set: { viewModel.joinCode = $0 }
                    ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .multilineTextAlignment(.center)

                    Button {
                        viewModel.joinSession()
                    } label: {
                        Label("watchTogether.join.button", systemImage: "person.badge.plus")
                            .frame(minWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .disabled(viewModel.joinCode.count < 4 || isConnecting)
                }
            }
        }
        .padding(32)
    }

    private var lobbyView: some View {
        VStack(spacing: 24) {
            if !viewModel.code.isEmpty {
                VStack(spacing: 8) {
                    Text("watchTogether.lobby.code")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(viewModel.code)
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                }
            }

            if !viewModel.participants.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("watchTogether.lobby.participants")
                        .font(.headline)

                    ForEach(viewModel.participants) { participant in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.brandPrimary)
                            Text(participant.displayName)
                            Spacer()
                            if participant.isReady {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(maxWidth: 400)
            }

            HStack(spacing: 16) {
                if viewModel.isHost {
                    Button {
                        viewModel.startPlayback()
                    } label: {
                        Label("watchTogether.lobby.start", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandSecondary)
                    .disabled(!viewModel.canStartPlayback)
                }

                Button(role: .destructive) {
                    isShowingLeaveAlert = true
                } label: {
                    Label("watchTogether.lobby.leave", systemImage: "door.left.hand.open")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .padding(32)
    }

    private func panelView(title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title2.bold())

            content()
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
