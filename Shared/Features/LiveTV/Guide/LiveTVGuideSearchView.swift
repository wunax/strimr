import SwiftUI

/// Finds channels and the programs of the next 24 hours, which it loads apart from the range the guide shows.
struct LiveTVGuideSearchView: View {
    private static let window: TimeInterval = 24 * 3600

    @Bindable var store: LiveTVStore
    let onSelectChannel: (LiveTVChannel) -> Void
    let onSelectProgram: (LiveTVProgram) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var loadedPrograms: [LiveTVProgram]?
    @State private var isLoadingPrograms = true

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
        Self.matchingPrograms(loadedPrograms ?? store.programs, query: trimmedQuery, now: Date())
    }

    static func matchingPrograms(_ programs: [LiveTVProgram], query: String, now: Date) -> [LiveTVProgram] {
        guard !query.isEmpty else { return [] }
        let limit = now.addingTimeInterval(window)
        return programs
            .filter { $0.endDate > now && $0.startDate < limit }
            .filter {
                $0.title.localizedStandardContains(query)
                    || ($0.seriesTitle?.localizedStandardContains(query) ?? false)
            }
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        TaskModalNavigationView {
            content
            #if !os(tvOS)
                .searchable(text: $query, prompt: Text("livetv.search.prompt"))
            #endif
                .taskModalTitle("livetv.search.title")
                .taskModalActions {
                    Button("common.done") { dismiss() }
                }
        }
        .task { await loadPrograms() }
    }

    private func loadPrograms() async {
        let now = Date()
        do {
            loadedPrograms = try await store.service.programs(from: now, to: now.addingTimeInterval(Self.window))
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            LiveTVErrorReporting.capture(error)
        }
        isLoadingPrograms = false
    }

    private var content: some View {
        #if os(tvOS)
            // Outside the list: a list row is rebuilt whenever the results change, which closes the keyboard.
            VStack(spacing: 24) {
                TextField("livetv.search.prompt", text: $query)
                results
            }
        #else
            results
        #endif
    }

    private var results: some View {
        // The filters read a day of programs: once per update, not once per use.
        let channels = channels
        let programs = programs
        return List {
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
            if !trimmedQuery.isEmpty {
                if isLoadingPrograms {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if channels.isEmpty, programs.isEmpty {
                    Text("livetv.search.empty")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func subtitle(_ program: LiveTVProgram) -> String {
        let time = program.startDate.formatted(.dateTime.weekday().hour().minute())
        let channel = store.channel(for: program.channelIdentity)?.displayTitle
        return [time, channel].compactMap(\.self).joined(separator: " · ")
    }
}
