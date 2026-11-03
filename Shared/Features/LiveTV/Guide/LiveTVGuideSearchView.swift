import SwiftUI

/// Finds channels and the programs of the next 24 hours among what the guide has loaded.
struct LiveTVGuideSearchView: View {
    @Bindable var store: LiveTVStore
    let onSelectChannel: (LiveTVChannel) -> Void
    let onSelectProgram: (LiveTVProgram) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var channels: [LiveTVChannel] {
        guard !trimmedQuery.isEmpty else { return [] }
        return store.channels.filter {
            $0.displayTitle.localizedStandardContains(trimmedQuery) || $0.title.localizedStandardContains(trimmedQuery)
        }
    }

    private var programs: [LiveTVProgram] {
        guard !trimmedQuery.isEmpty else { return [] }
        let now = Date()
        let limit = now.addingTimeInterval(24 * 3600)
        return store.programs
            .filter { $0.endDate > now && $0.startDate < limit }
            .filter {
                $0.title.localizedStandardContains(trimmedQuery)
                    || ($0.seriesTitle?.localizedStandardContains(trimmedQuery) ?? false)
            }
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        TaskModalNavigationView {
            List {
                #if os(tvOS)
                    TextField("livetv.search.prompt", text: $query)
                #endif
                if !channels.isEmpty {
                    Section("livetv.search.channels") {
                        ForEach(channels) { channel in
                            Button {
                                dismiss()
                                onSelectChannel(channel)
                            } label: {
                                HStack(spacing: 12) {
                                    LiveTVChannelLogo(channel: channel)
                                        .frame(width: 56, height: 32)
                                    Text(channel.displayTitle)
                                }
                            }
                        }
                    }
                }
                if !programs.isEmpty {
                    Section("livetv.search.programs") {
                        ForEach(programs) { program in
                            Button {
                                dismiss()
                                onSelectProgram(program)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(program.title)
                                    Text(subtitle(program))
                                        .font(.cardMetadata)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !trimmedQuery.isEmpty, channels.isEmpty, programs.isEmpty {
                    Text("livetv.search.empty")
                        .foregroundStyle(.secondary)
                }
            }
            #if !os(tvOS)
            .searchable(text: $query, prompt: Text("livetv.search.prompt"))
            #endif
            .taskModalTitle("livetv.search.title")
            .taskModalActions {
                Button("common.done") { dismiss() }
            }
        }
    }

    private func subtitle(_ program: LiveTVProgram) -> String {
        let time = program.startDate.formatted(.dateTime.weekday().hour().minute())
        let channel = store.channel(for: program.channelIdentity)?.displayTitle
        return [time, channel].compactMap(\.self).joined(separator: " · ")
    }
}
