#if os(iOS) || os(macOS)
    import SwiftUI

    struct PlexStopPlaybackView: View {
        @Environment(\.dismiss) private var dismiss
        let play: PlexDashboardPlay
        let model: PlexDashboardViewModel
        @State private var reason = ""
        @State private var isStopping = false
        @State private var error: String?

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        LabeledContent("plex.dashboard.stop.media", value: play.title)
                        LabeledContent("plex.dashboard.user", value: play.userName ?? model.userName(play.accountID))
                        if let player = play.player {
                            LabeledContent("plex.dashboard.stop.device", value: player)
                        }
                    }
                    Section {
                        TextField("plex.dashboard.stop.reason", text: $reason, axis: .vertical)
                            .lineLimit(3 ... 5)
                            .disabled(isStopping)
                    } footer: {
                        Text("plex.dashboard.stop.explanation")
                    }
                    if let error {
                        Section {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button(role: .destructive) { isStopping = true } label: {
                            HStack {
                                Text("plex.dashboard.stop.title")
                                Spacer()
                                if isStopping {
                                    ProgressView()
                                }
                            }.frame(minHeight: 44)
                        }
                        .disabled(isStopping || play.sessionID?.isEmpty != false)
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("plex.dashboard.stop.title")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.actions.cancel", role: .cancel) { dismiss() }
                                .disabled(isStopping)
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 420, idealWidth: 480, minHeight: 440)
            #endif
            .interactiveDismissDisabled(isStopping)
            .task(id: isStopping) {
                guard isStopping, let sessionID = play.sessionID else { return }
                error = nil
                defer { isStopping = false }
                do {
                    try await model.repository.stopPlayback(
                        sessionID: sessionID,
                        reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                    )
                    try Task.checkCancellation()
                    await model.refreshLive()
                    dismiss()
                } catch {
                    guard !Task.isCancelled else { return }
                    if case let PlexAPIError.requestFailed(code) = error, code == 401 || code == 403 {
                        self.error = String(localized: "plex.dashboard.stop.denied")
                    } else if case PlexAPIError.requestFailed(404) = error {
                        self.error = String(localized: "plex.dashboard.stop.ended")
                    } else {
                        self.error = String(localized: "plex.dashboard.stop.failed")
                    }
                }
            }
        }
    }
#endif
