import SwiftUI

struct LiveTVView: View {
    private enum GuideFocusItem: Hashable {
        case favorite(String)
        case channel(String)
        case program(String)
        case onNowProgram(String)
    }

    enum LiveTVSection: String, CaseIterable, Identifiable {
        case guide
        case onNow
        case dvr

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .guide: "livetv.section.guide"
            case .onNow: "livetv.section.onNow"
            case .dvr: "livetv.section.dvr"
            }
        }
    }

    @Bindable var store: LiveTVStore
    let onPlayLive: (LiveTVLaunchContext) -> Void
    let onPlayRecording: (MediaItem) -> Void
    let onOpenLibrary: (String) -> Void

    @State private var section = LiveTVSection.guide
    @State private var favoritesOnly = false
    @State private var selectedProgram: LiveTVProgram?
    @State private var pendingRecordingDeletion: DVRRecording?
    @State private var isManagingFavorites = false
    @State private var selectedRule: DVRRecordingRule?
    #if os(tvOS)
        @FocusState private var focusedGuideItem: GuideFocusItem?
    #endif

    var body: some View {
        VStack(spacing: 12) {
            Picker("livetv.title", selection: $section) {
                ForEach(LiveTVSection.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if store.isLoading, store.channels.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if !store.isAvailable {
                emptyState("livetv.unavailable", systemImage: "tv.slash")
            } else if store.channels.isEmpty {
                emptyState("livetv.empty.channels", systemImage: "tv")
            } else {
                switch section {
                case .guide: guide
                case .onNow: onNow
                case .dvr: dvr
                }
            }
        }
        .navigationTitle("livetv.title")
        .toolbar {
            ToolbarItemGroup {
                if section == .guide {
                    Toggle("livetv.favoritesOnly", systemImage: "star.fill", isOn: $favoritesOnly)
                    Button("livetv.favorites.manage", systemImage: "arrow.up.arrow.down") {
                        isManagingFavorites = true
                    }
                }
                Button("common.refresh", systemImage: "arrow.clockwise") {
                    Task { await store.load(start: store.guideStart, force: true) }
                }
            }
        }
        .task { await store.load() }
        .sheet(item: $selectedProgram) { program in
            LiveTVProgramDetailView(
                program: program,
                channel: store.channels.first { $0.id == program.channelID },
                dvr: store.dvr,
                supportsWatchFromStart: store.service.supportsServerCaptureBuffer,
                onWatch: { tune(program) },
                onWatchFromStart: { tune(program, fromStart: true) },
                onChanged: { await store.refreshDVR() },
            )
        }
        .sheet(isPresented: $isManagingFavorites) {
            FavoriteChannelOrderView(store: store)
        }
        .sheet(item: $selectedRule) { rule in
            DVRRuleEditView(rule: rule, dvr: store.dvr) { await store.refreshDVR() }
        }
        .confirmationDialog(
            "livetv.recording.delete.confirm",
            isPresented: Binding(
                get: { pendingRecordingDeletion != nil },
                set: { if !$0 { pendingRecordingDeletion = nil } },
            ),
            titleVisibility: .visible,
        ) {
            Button("common.delete", role: .destructive) {
                guard let recording = pendingRecordingDeletion, let dvr = store.dvr else { return }
                Task {
                    do {
                        try await dvr.deleteCompleted(recordingID: recording.id)
                        await store.refreshDVR()
                    } catch {
                        guard !Task.isCancelled, !error.isCancellation else { return }
                        LiveTVErrorReporting.capture(error)
                    }
                }
            }
        }
    }

    private var displayedChannels: [LiveTVChannel] {
        favoritesOnly ? store.channels.filter(\.isFavorite) : store.channels
    }

    private var guide: some View {
        VStack(spacing: 8) {
            HStack {
                Button("livetv.guide.previous", systemImage: "chevron.left") { Task { await store.shiftGuide(hours: -6) } }
                Spacer()
                Text(store.guideStart, format: .dateTime.weekday().month().day())
                Spacer()
                Button("livetv.guide.now") { Task { await store.jumpToNow() } }
                Button("livetv.guide.next", systemImage: "chevron.right") { Task { await store.shiftGuide(hours: 24) } }
            }
            .padding(.horizontal)

            if displayedChannels.isEmpty {
                emptyState("livetv.empty.favorites", systemImage: "star")
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(displayedChannels) { channel in guideRow(channel) }
                        } header: {
                            guideHeader
                                .background(.regularMaterial)
                        }
                    }
                    .padding(.horizontal)
                    .overlay(alignment: .topLeading) {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            if store.guideStart <= context.date, context.date < store.guideEnd {
                                Rectangle()
                                    .fill(.red)
                                    .frame(width: 2, height: CGFloat(displayedChannels.count * 68 + 28))
                                    .offset(
                                        x: 186 + context.date.timeIntervalSince(store.guideStart) / 15,
                                        y: 24,
                                    )
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var guideHeader: some View {
        HStack(spacing: 0) {
            Text("livetv.channel").frame(width: 170, alignment: .leading)
            ForEach(0..<12, id: \.self) { index in
                Text(store.guideStart.addingTimeInterval(Double(index) * 1800), format: .dateTime.hour().minute())
                    .font(.caption)
                    .frame(width: 120, alignment: .leading)
            }
        }
    }

    private func guideRow(_ channel: LiveTVChannel) -> some View {
        #if os(tvOS)
            let isFavoriteFocused = focusedGuideItem == .favorite(channel.id)
            let isChannelFocused = focusedGuideItem == .channel(channel.id)
        #else
            let isFavoriteFocused = false
            let isChannelFocused = false
        #endif

        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                Group {
                    #if os(tvOS)
                        guideFavoriteLabel(channel, isFocused: isFavoriteFocused)
                            .focusable()
                            .focused($focusedGuideItem, equals: .favorite(channel.id))
                            .onTapGesture { Task { await store.toggleFavorite(channel) } }
                            .accessibilityAddTraits(.isButton)
                    #else
                        Button { Task { await store.toggleFavorite(channel) } } label: {
                            guideFavoriteLabel(channel, isFocused: false)
                        }
                        .buttonStyle(.plain)
                    #endif
                }
                .animation(.easeOut(duration: 0.15), value: isFavoriteFocused)
                .accessibilityLabel(
                    Text(channel.isFavorite ? "livetv.favorite.remove" : "livetv.favorite.add"),
                )

                Group {
                    #if os(tvOS)
                        guideChannelLabel(channel, isFocused: isChannelFocused)
                            .focusable()
                            .focused($focusedGuideItem, equals: .channel(channel.id))
                            .onTapGesture { tune(channel) }
                            .accessibilityAddTraits(.isButton)
                    #else
                        Button { tune(channel) } label: {
                            guideChannelLabel(channel, isFocused: false)
                        }
                        .buttonStyle(.plain)
                    #endif
                }
                .animation(.easeOut(duration: 0.15), value: isChannelFocused)
                .accessibilityLabel(Text("livetv.channel.watch \(channel.displayTitle)"))
            }
            .frame(width: 160, alignment: .leading)

            let programs = store.programs.filter { $0.channelID == channel.id && $0.endDate > store.guideStart && $0.startDate < store.guideEnd }
            ZStack(alignment: .leading) {
                if programs.isEmpty {
                    Text("livetv.guide.noData").foregroundStyle(.secondary)
                } else {
                    ForEach(programs) { program in
                        let visibleStart = max(program.startDate, store.guideStart)
                        let visibleEnd = min(program.endDate, store.guideEnd)
                        #if os(tvOS)
                            let isFocused = focusedGuideItem == .program(program.id)
                        #else
                            let isFocused = false
                        #endif
                        Group {
                            #if os(tvOS)
                                guideProgramLabel(
                                    program,
                                    width: max(4, visibleEnd.timeIntervalSince(visibleStart) / 15 - 4),
                                    isFocused: isFocused,
                                )
                                .focusable()
                                .focused($focusedGuideItem, equals: .program(program.id))
                                .onTapGesture { selectedProgram = program }
                                .accessibilityAddTraits(.isButton)
                            #else
                                Button { selectedProgram = program } label: {
                                    guideProgramLabel(
                                        program,
                                        width: max(4, visibleEnd.timeIntervalSince(visibleStart) / 15 - 4),
                                        isFocused: false,
                                    )
                                }
                                .buttonStyle(.plain)
                            #endif
                        }
                        .offset(x: visibleStart.timeIntervalSince(store.guideStart) / 15)
                        .zIndex(isFocused ? 1 : 0)
                        .animation(.easeOut(duration: 0.15), value: isFocused)
                    }
                }
            }
            .frame(width: 1440, height: 64, alignment: .leading)
            .clipped()
        }
    }

    private func guideFavoriteLabel(_ channel: LiveTVChannel, isFocused: Bool) -> some View {
        Image(systemName: channel.isFavorite ? "star.fill" : "star")
            .foregroundStyle(channel.isFavorite ? .yellow : .secondary)
            .frame(width: 34, height: 34)
            .background {
                Circle()
                    .fill(.white.opacity(isFocused ? 0.18 : 0))
            }
            .overlay {
                Circle()
                    .stroke(.white.opacity(isFocused ? 0.9 : 0), lineWidth: 2)
            }
            .scaleEffect(isFocused ? 1.08 : 1)
            .contentShape(Circle())
    }

    private func guideChannelLabel(_ channel: LiveTVChannel, isFocused: Bool) -> some View {
        Text(channel.displayTitle)
            .lineLimit(2)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(isFocused ? 0.16 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(isFocused ? 0.85 : 0), lineWidth: 2)
            }
            .scaleEffect(isFocused ? 1.025 : 1)
            .contentShape(Rectangle())
    }

    private func guideProgramLabel(_ program: LiveTVProgram, width: CGFloat, isFocused: Bool) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(program.title)
                    .font(guideProgramTitleFont)
                    .lineLimit(1)
                if program.recordingID != nil || program.seriesRecordingID != nil {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                }
            }
            Text(program.startDate, format: .dateTime.hour().minute())
                .font(guideProgramTimeFont)
        }
        .padding(8)
        .frame(width: width, height: 64, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(guideProgramBackground(program, isFocused: isFocused))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    program.isCurrentlyAiring ? Color.accentColor : Color.white,
                    lineWidth: isFocused ? 3 : 0,
                )
        }
        .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 10, y: 5)
        .scaleEffect(isFocused ? 1.025 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func guideProgramBackground(_ program: LiveTVProgram, isFocused: Bool) -> Color {
        if program.isCurrentlyAiring {
            return Color.accentColor.opacity(isFocused ? 0.42 : 0.25)
        }
        return Color.secondary.opacity(isFocused ? 0.28 : 0.12)
    }

    private var guideProgramTitleFont: Font {
        #if os(tvOS)
            .subheadline
        #else
            .headline
        #endif
    }

    private var guideProgramTimeFont: Font {
        #if os(tvOS)
            .caption2
        #else
            .caption
        #endif
    }

    private var onNow: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if store.onNowSections.isEmpty {
                    emptyState("livetv.empty.onNow", systemImage: "clock")
                }
                ForEach(store.onNowSections) { row in
                    VStack(alignment: .leading) {
                        Text(row.title).font(.title2.bold())
                        ScrollView(.horizontal) {
                            LazyHStack {
                                ForEach(row.programs) { program in
                                    #if os(tvOS)
                                        let isFocused = focusedGuideItem == .onNowProgram(program.id)
                                    #else
                                        let isFocused = false
                                    #endif
                                    Group {
                                        #if os(tvOS)
                                            onNowProgramCard(program, isFocused: isFocused)
                                                .focusable()
                                                .focused($focusedGuideItem, equals: .onNowProgram(program.id))
                                                .onTapGesture { openOnNowProgram(program) }
                                                .accessibilityAddTraits(.isButton)
                                        #else
                                            Button { openOnNowProgram(program) } label: {
                                                onNowProgramCard(program, isFocused: false)
                                            }
                                            .buttonStyle(.plain)
                                        #endif
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(
                                        Text(
                                            "livetv.onNow.program.accessibility \(program.title) \(channelName(program.channelID))",
                                        ),
                                    )
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }
                }
            }
            .padding()
        }
    }

    private func onNowProgramCard(_ program: LiveTVProgram, isFocused: Bool) -> some View {
        VStack(alignment: .leading) {
            Group {
                if let artworkPath = program.artPath ?? program.thumbPath {
                    ArtworkPathView(
                        path: artworkPath,
                        width: 480,
                        height: 270,
                    )
                } else {
                    MediaArtworkPlaceholder(mediaKind: .episode)
                }
            }
            .frame(width: 240, height: 135)
            .mediaArtworkStyle(.compact)
            .scaleEffect(isFocused ? 1.12 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)

            Text(program.title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(channelName(program.channelID))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 240, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func openOnNowProgram(_ program: LiveTVProgram) {
        if program.isCurrentlyAiring {
            tune(program)
        } else {
            selectedProgram = program
        }
    }

    private var dvr: some View {
        List {
            if store.dvr == nil {
                Text("livetv.dvr.unsupported")
            } else if store.dvr?.canManageRecordings == false {
                Text("livetv.dvr.permissionDenied")
            }

            Section("livetv.dvr.upcoming") {
                if store.upcomingRecordings.isEmpty { Text("livetv.empty.recordings") }
                ForEach(store.upcomingRecordings) { recording in
                    recordingRow(recording)
                        .contextMenu {
                            Button("common.cancel", role: .destructive) { cancel(recording) }
                        }
                }
            }
            Section("livetv.dvr.rules") {
                ForEach(store.recordingRules) { rule in
                    VStack(alignment: .leading) {
                        Button { selectedRule = rule } label: {
                            VStack(alignment: .leading) {
                                Text(rule.title)
                                if let library = rule.targetLibraryTitle { Text(library).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        if let libraryID = rule.targetLibraryID {
                            Button("livetv.dvr.openLibrary", systemImage: "rectangle.stack") { onOpenLibrary(libraryID) }
                        }
                    }
                    .contextMenu {
                        Button("common.delete", role: .destructive) { delete(rule) }
                    }
                }
            }
            if store.dvr?.supportsCompletedRecordings == true {
                Section("livetv.dvr.completed") {
                    ForEach(store.completedRecordings) { recording in
                        Button { if let media = recording.playableMedia { onPlayRecording(media) } } label: {
                            recordingRow(recording)
                        }
                        .contextMenu {
                            if store.dvr?.canDeleteRecordings == true {
                                Button("common.delete", role: .destructive) { pendingRecordingDeletion = recording }
                            }
                        }
                    }
                }
            }
        }
    }

    private func recordingRow(_ recording: DVRRecording) -> some View {
        VStack(alignment: .leading) {
            Text(recording.title)
            HStack {
                if let channel = recording.channelTitle { Text(channel) }
                if let start = recording.startDate { Text(start, format: .dateTime.weekday().hour().minute()) }
                Text(recording.status.localizedTitle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func tune(_ program: LiveTVProgram, fromStart: Bool = false) {
        guard let index = store.channels.firstIndex(where: { $0.id == program.channelID }) else { return }
        onPlayLive(
            LiveTVLaunchContext(
                channels: store.channels,
                selectedIndex: index,
                program: program,
                startsFromBeginning: fromStart,
            ),
        )
    }

    private func tune(_ channel: LiveTVChannel) {
        guard let index = store.channels.firstIndex(where: { $0.id == channel.id }) else { return }
        onPlayLive(LiveTVLaunchContext(channels: store.channels, selectedIndex: index))
    }

    private func channelName(_ id: String) -> String {
        store.channels.first { $0.id == id }?.displayTitle ?? ""
    }

    private func cancel(_ recording: DVRRecording) {
        guard let dvr = store.dvr else { return }
        Task {
            do {
                try await dvr.cancel(recordingID: recording.id)
                await store.refreshDVR()
            } catch {
                LiveTVErrorReporting.capture(error)
            }
        }
    }

    private func delete(_ rule: DVRRecordingRule) {
        guard let dvr = store.dvr else { return }
        Task {
            do {
                try await dvr.delete(ruleID: rule.id)
                await store.refreshDVR()
            } catch {
                LiveTVErrorReporting.capture(error)
            }
        }
    }

    private func emptyState(_ key: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(key).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let message = store.errorMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private extension DVRRecordingStatus {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .scheduled: "livetv.recording.status.scheduled"
        case .recording: "livetv.recording.status.recording"
        case .completed: "livetv.recording.status.completed"
        case .cancelled: "livetv.recording.status.cancelled"
        case .error: "livetv.recording.status.error"
        case .unknown: "livetv.recording.status.unknown"
        }
    }
}

private struct DVRRuleEditView: View {
    let rule: DVRRecordingRule
    let dvr: (any MediaDVRService)?
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String]
    @State private var errorMessage: String?

    init(rule: DVRRecordingRule, dvr: (any MediaDVRService)?, onChanged: @escaping () async -> Void) {
        self.rule = rule
        self.dvr = dvr
        self.onChanged = onChanged
        _values = State(initialValue: rule.optionValues)
    }

    var body: some View {
        NavigationStack {
            Form {
                Text(rule.title).font(.title2.bold())
                ForEach(values.keys.sorted(), id: \.self) { key in
                    TextField(key, text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }))
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("livetv.dvr.editRule")
            .toolbar {
                Button("common.cancel") { dismiss() }
                Button("common.done") { save() }
            }
        }
    }

    private func save() {
        guard let dvr else { return }
        Task {
            do {
                try await dvr.update(rule: rule, options: values)
                await onChanged()
                dismiss()
            } catch {
                LiveTVErrorReporting.capture(error)
                errorMessage = String(localized: "livetv.dvr.updateError")
            }
        }
    }
}

private struct FavoriteChannelOrderView: View {
    @Bindable var store: LiveTVStore
    @Environment(\.dismiss) private var dismiss
    @State private var favorites: [LiveTVChannel] = []

    var body: some View {
        NavigationStack {
            List {
                if favorites.isEmpty { Text("livetv.empty.favorites") }
                ForEach(Array(favorites.enumerated()), id: \.element.id) { index, channel in
                    HStack {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(channel.displayTitle)
                        Spacer()
                        Button("livetv.favorites.moveUp", systemImage: "chevron.up") { move(index, by: -1) }
                            .labelStyle(.iconOnly)
                            .disabled(index == 0)
                        Button("livetv.favorites.moveDown", systemImage: "chevron.down") { move(index, by: 1) }
                            .labelStyle(.iconOnly)
                            .disabled(index + 1 == favorites.count)
                    }
                }
            }
            .navigationTitle("livetv.favorites.manage")
            .toolbar { Button("common.done") { dismiss() } }
            .onAppear { favorites = store.channels.filter(\.isFavorite) }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard favorites.indices.contains(destination) else { return }
        favorites.swapAt(index, destination)
        let reordered = favorites
        Task {
            do {
                try await store.reorderFavorites(reordered)
            } catch {
                LiveTVErrorReporting.capture(error)
            }
        }
    }
}

private struct LiveTVProgramDetailView: View {
    let program: LiveTVProgram
    let channel: LiveTVChannel?
    let dvr: (any MediaDVRService)?
    let supportsWatchFromStart: Bool
    let onWatch: () -> Void
    let onWatchFromStart: () -> Void
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var template: DVRRecordingTemplate?
    @State private var recordsSeries = false
    @State private var optionValues: [String: String] = [:]
    @State private var targetLibraryID: String?
    @State private var errorMessage: String?
    @State private var isSubmittingRecording = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(program.title).font(.title2.bold())
                    if let channel { Text(channel.displayTitle) }
                    Text(program.startDate.formatted(date: .abbreviated, time: .shortened) + " – " + program.endDate.formatted(date: .omitted, time: .shortened))
                    if let summary = program.summary { Text(summary) }
                    if program.isCurrentlyAiring { ProgressView(value: program.progress) }
                }
                if let template, !program.isScheduledForRecording {
                    if !template.libraries.isEmpty {
                        Picker("livetv.recording.library", selection: $targetLibraryID) {
                            ForEach(template.libraries) { Text($0.title).tag(Optional($0.id)) }
                        }
                    }
                    if template.supportsSingle && template.supportsSeries {
                        Picker("livetv.recording.mode", selection: $recordsSeries) {
                            Text("livetv.record").tag(false)
                            Text("livetv.recordSeries").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    ForEach(template.options.filter { recordsSeries || !template.seriesOnlyOptionIDs.contains($0.id) }) { option in
                        optionEditor(option)
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("livetv.program.details")
            .toolbar {
                ToolbarItemGroup {
                    if program.isCurrentlyAiring {
                        Button("livetv.watchLive", action: onWatch)
                        if supportsWatchFromStart {
                            Button("livetv.watchFromStart", action: onWatchFromStart)
                        }
                    }
                    if dvr?.canManageRecordings == true {
                        if program.isScheduledForRecording {
                            Button("livetv.stopRecord", role: .destructive) {
                                stopRecording()
                            }
                            .disabled(isSubmittingRecording)
                        } else {
                            if template?.supportsSingle == true {
                                Button("livetv.record") { schedule(series: false) }
                                    .disabled(template == nil || isSubmittingRecording)
                            }
                            if template?.supportsSeries == true {
                                Button("livetv.recordSeries") { schedule(series: true) }
                                    .disabled(template == nil || isSubmittingRecording)
                            }
                        }
                    }
                    Button("common.done") { dismiss() }
                }
            }
            .task {
                guard !program.isScheduledForRecording, let dvr, dvr.canManageRecordings else { return }
                do {
                    let value = try await dvr.recordingTemplate(for: program)
                    template = value
                    recordsSeries = !value.supportsSingle && value.supportsSeries
                    optionValues = Dictionary(uniqueKeysWithValues: value.options.map { ($0.id, $0.defaultValue) })
                    targetLibraryID = value.defaultLibraryID
                } catch {
                    guard !Task.isCancelled, !error.isCancellation else { return }
                    LiveTVErrorReporting.capture(error)
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder private func optionEditor(_ option: DVRRecordingOption) -> some View {
        switch option.kind {
        case .toggle:
            Toggle(option.title, isOn: Binding(
                get: { optionValues[option.id] == "true" },
                set: { optionValues[option.id] = String($0) },
            ))
        case let .choice(choices):
            Picker(option.title, selection: valueBinding(option)) {
                ForEach(choices) { Text($0.title).tag($0.id) }
            }
        case .integer, .text:
            VStack(alignment: .leading, spacing: 6) {
                Text(option.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(text: valueBinding(option)) {
                    Text(option.title)
                }
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private func valueBinding(_ option: DVRRecordingOption) -> Binding<String> {
        Binding(get: { optionValues[option.id] ?? option.defaultValue }, set: { optionValues[option.id] = $0 })
    }

    private func schedule(series: Bool) {
        guard let dvr else { return }
        recordsSeries = series
        isSubmittingRecording = true
        Task {
            do {
                try await dvr.schedule(.init(program: program, recordsSeries: series, targetLibraryID: targetLibraryID, options: optionValues))
                await onChanged()
                dismiss()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                switch error {
                case let error as JellyfinAPIError where error == .recordingConflict:
                    break
                default:
                    LiveTVErrorReporting.capture(error)
                }
                errorMessage = error.localizedDescription
                isSubmittingRecording = false
            }
        }
    }

    private func stopRecording() {
        guard let dvr, let recordingID = program.recordingID ?? program.seriesRecordingID else { return }
        isSubmittingRecording = true
        Task {
            do {
                try await dvr.cancel(recordingID: recordingID)
                await onChanged()
                dismiss()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                LiveTVErrorReporting.capture(error)
                errorMessage = error.localizedDescription
                isSubmittingRecording = false
            }
        }
    }
}
