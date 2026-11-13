#if os(iOS) || os(macOS)
    import SwiftUI

    struct PlexServerView: View {
        @Environment(ServerRegistry.self) private var registry
        @State private var selectedServer: ServerIdentity?
        @State private var detailError: String?
        @State private var detailTask: Task<Void, Never>?
        let onSelectMedia: (MediaItem) -> Void

        private var servers: [ServerSession] {
            registry.administeredPlexServers
        }

        private var server: ServerSession? {
            servers.first { $0.identity == selectedServer } ?? servers.first
        }

        var body: some View {
            Group {
                if let server, let context = registry.plexAdministrationContext(for: server.identity), server.isActive {
                    PlexDashboardView(
                        repository: PlexDashboardRepository(context: context),
                        serverName: server.name,
                    ) { key in
                        openDetail(key, on: server.identity)
                    }
                    .id("\(registry.generation)|\(server.identity.id)")
                } else {
                    ContentUnavailableView {
                        Label("plex.dashboard.unavailable.title", systemImage: "server.rack")
                    } description: {
                        if servers.isEmpty {
                            Text("plex.dashboard.unavailable.owner")
                        } else {
                            Text("plex.dashboard.unavailable.connection")
                        }
                    } actions: {
                        Button("common.actions.retry") { registry.retryUnavailable() }
                    }
                }
            }
            .navigationTitle("plex.dashboard.title")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    if servers.count > 1 {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Picker("plex.dashboard.server", selection: Binding(
                                    get: { server?.identity }, set: { selectedServer = $0 },
                                )) {
                                    ForEach(servers) { server in
                                        Text(server.name).tag(Optional(server.identity))
                                    }
                                }
                            } label: { Image(systemName: "server.rack") }
                                .accessibilityLabel("plex.dashboard.server")
                        }
                    }
                }
                .alert("plex.dashboard.error.detailTitle", isPresented: Binding(
                    get: { detailError != nil }, set: {
                        if !$0 {
                            detailError = nil
                        }
                    },
                )) {
                    Button("common.actions.close", role: .cancel) { detailError = nil }
                } message: { Text(detailError ?? "") }
                .onDisappear { detailTask?.cancel() }
        }

        /// Only the latest tap opens a detail page, and nothing opens once the dashboard is gone.
        private func openDetail(_ key: String, on server: ServerIdentity) {
            guard !key.isEmpty, let services = registry.services(for: server) else { return }
            detailTask?.cancel()
            let generation = registry.generation
            detailTask = Task {
                do {
                    let media = try await services.detail.mediaItem(id: key)
                    guard !Task.isCancelled, generation == registry.generation else { return }
                    onSelectMedia(media)
                } catch {
                    guard !Task.isCancelled else { return }
                    detailError = String(localized: "plex.dashboard.error.detail")
                }
            }
        }
    }

    /// The Plex chevron is supplied as a vector asset, sized like the other native menu icons.
    struct PlexServerIcon: View {
        var body: some View {
            Image("PlexMark")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }

    private struct PlexDashboardView: View {
        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @State private var model: PlexDashboardViewModel
        @State private var stopTarget: PlexDashboardPlay?
        @State private var isRefreshing = false
        let serverName: String
        let onSelect: (String) -> Void

        init(repository: PlexDashboardRepository, serverName: String, onSelect: @escaping (String) -> Void) {
            _model = State(initialValue: PlexDashboardViewModel(repository: repository))
            self.serverName = serverName
            self.onSelect = onSelect
        }

        private var isLive: Bool {
            scenePhase == .active && model.tab == .dashboard
        }

        var body: some View {
            List {
                Section {
                    if dynamicTypeSize.isAccessibilitySize {
                        tabPicker.pickerStyle(.menu)
                    } else {
                        tabPicker.pickerStyle(.segmented)
                    }
                } header: {
                    Text(serverName).textCase(nil)
                }
                switch model.tab {
                case .dashboard: dashboard
                case .history: history
                case .topPlayed: topPlayed
                }
            }
            .insetListStyle()
            .task { await model.loadFilters() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("plex.dashboard.refresh")
                    .disabled(isRefreshing)
                }
            }
            .task(id: isLive) {
                if isLive {
                    await model.poll()
                }
            }
            .task(id: "\(model.tab.rawValue)|\(model.period.rawValue)") {
                switch model.tab {
                case .dashboard: await model.loadActivity()
                case .topPlayed: await model.loadRankings()
                case .history: break
                }
            }
            .task(id: "\(model.tab.rawValue)|\(model.historyFilterID)") {
                if model.tab == .history {
                    await model.loadHistory(reset: true)
                }
            }
            .refreshable { await refresh() }
            .sheet(item: $stopTarget) { play in
                PlexStopPlaybackView(play: play, model: model)
            }
        }

        private func refresh() async {
            isRefreshing = true
            defer { isRefreshing = false }
            await model.loadFilters()
            switch model.tab {
            case .dashboard:
                await model.refreshLive()
                await model.loadActivity()
            case .history: await model.loadHistory(reset: true)
            case .topPlayed: await model.loadRankings(force: true)
            }
        }

        private var tabPicker: some View {
            Picker("plex.dashboard.section", selection: $model.tab) {
                ForEach(PlexDashboardTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .labelsHidden()
        }

        @ViewBuilder private var dashboard: some View {
            Section {
                if let error = model.errors[.sessions] {
                    status(error, symbol: "wifi.exclamationmark")
                } else if model.loading.contains(.sessions), model.updatedAt == nil {
                    ProgressView()
                } else if model.sessions.isEmpty {
                    status(String(localized: "plex.dashboard.noStreams"), symbol: "play.rectangle")
                } else {
                    ForEach(model.sessions) { play in
                        liveSession(play)
                    }
                }
            } header: { Text("plex.dashboard.nowPlaying") } footer: {
                if let updatedAt = model.updatedAt {
                    Text("plex.dashboard.updated \(updatedAt.formatted(date: .omitted, time: .standard))")
                }
            }

            metric(
                "plex.dashboard.bandwidth",
                points: model.bandwidth,
                unit: "Mbps",
                errorKey: .bandwidth,
                percentage: false,
            )
            metric("plex.dashboard.cpu", points: model.cpu, unit: "%", errorKey: .resources, percentage: true)
            metric("plex.dashboard.memory", points: model.memory, unit: "%", errorKey: .resources, percentage: true)

            Section {
                periodPicker
                if let error = model.errors[.activity] {
                    status(error, symbol: "chart.bar.xaxis")
                } else if model.loading.contains(.activity) {
                    ProgressView()
                } else if model.activity.isEmpty {
                    status(String(localized: "plex.dashboard.noActivity"), symbol: "chart.bar.xaxis")
                } else {
                    PlexActivityChart(points: model.activityPoints)
                        .padding(.vertical, 8)
                }
            } header: { Text("plex.dashboard.playHistory") } footer: {
                Text("plex.dashboard.recordedTime")
            }

            if !model.topUsers.isEmpty {
                Section("plex.dashboard.topUsers") {
                    ForEach(model.topUsers) { user in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                PlexDashboardUserLabel(name: model.userName(user.id), url: model.userAvatar(user.id))
                                    .font(.headline)
                                Spacer()
                                Text(PlexDashboardFormatting.duration(user.duration))
                                    .foregroundStyle(.secondary)
                            }
                            Text("plex.dashboard.plays \(user.plays)").font(.subheadline).foregroundStyle(.secondary)
                            ForEach(
                                PlexDashboardMediaKind.allCases.filter { (user.breakdown[$0] ?? 0) > 0 },
                                id: \.self,
                            ) { kind in
                                LabeledContent {
                                    Text(PlexDashboardFormatting.duration(user.breakdown[kind] ?? 0))
                                } label: { Label(kind.title, systemImage: kind.symbol) }
                                    .font(.subheadline)
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }
            filterError
        }

        private func liveSession(_ play: PlexDashboardPlay) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    onSelect(play.ratingKey)
                } label: {
                    PlexDashboardMediaRow(
                        play: play,
                        repository: model.repository,
                        user: play.userName ?? model.userName(play.accountID),
                        avatarURL: model.repository.avatarURL(play.userThumb) ?? model.userAvatar(play.accountID),
                        live: true,
                    )
                }
                .buttonStyle(.plain)
                .disabled(!play.canOpenDetail)
                if !play.streamDetails.isEmpty || play.sessionID != nil {
                    DisclosureGroup("plex.dashboard.stream.details") {
                        ForEach(play.streamDetails) { detail in
                            LabeledContent {
                                Text(detail.value).textSelection(.enabled)
                            } label: {
                                Text(detail.field.title)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 3)
                        }
                        if let sessionID = play.sessionID, !sessionID.isEmpty {
                            Button(role: .destructive) {
                                stopTarget = play
                            } label: {
                                Label("plex.dashboard.stop.title", systemImage: "stop.circle")
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }

        private var periodPicker: some View {
            Picker("plex.dashboard.period", selection: $model.period) {
                ForEach(PlexDashboardPeriod.allCases.filter { $0 != .all }, id: \.self) { period in
                    Text(period.title).tag(period)
                }
            }
        }

        @ViewBuilder private var history: some View {
            Section {
                NavigationLink {
                    PlexDashboardUserPicker(model: model)
                } label: {
                    LabeledContent("plex.dashboard.user") {
                        if model.userID.isEmpty {
                            Text("plex.dashboard.allUsers")
                        } else {
                            PlexDashboardUserLabel(
                                name: model.userName(model.userID),
                                url: model.userAvatar(model.userID),
                            )
                        }
                    }
                }
                Picker("plex.dashboard.library", selection: $model.libraryID) {
                    Text("plex.dashboard.allLibraries").tag("")
                    ForEach(model.libraries) { Text($0.name).tag($0.id) }
                }
                Picker("plex.dashboard.period", selection: $model.historyPeriod) {
                    ForEach(PlexDashboardPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            filterError
            Section {
                ForEach(model.history) { play in
                    Button { onSelect(play.ratingKey) } label: {
                        PlexDashboardMediaRow(
                            play: play,
                            repository: model.repository,
                            user: model.userName(play.accountID),
                            avatarURL: model.userAvatar(play.accountID),
                            live: false,
                        )
                    }.buttonStyle(.plain)
                        .disabled(!play.canOpenDetail)
                }
                if let error = model.errors[.history] {
                    status(error, symbol: "exclamationmark.circle")
                    Button("common.actions.retry") { Task { await model.loadHistory(reset: model.history.isEmpty) } }
                } else if model.loading.contains(.history) {
                    ProgressView().frame(maxWidth: .infinity)
                } else if model.history.isEmpty {
                    status(String(localized: "plex.dashboard.noHistory"), symbol: "clock")
                } else if model.historyHasMore {
                    Button("plex.dashboard.loadMore") { Task { await model.loadHistory(reset: false) } }
                        .frame(maxWidth: .infinity)
                }
            }
        }

        @ViewBuilder private var topPlayed: some View {
            Section {
                periodPicker
                Picker("plex.dashboard.mediaType", selection: $model.kind) {
                    Text("plex.dashboard.allMedia").tag(PlexDashboardMediaKind?.none)
                    ForEach(PlexDashboardMediaKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
            }
            if model.rankingsIncomplete {
                Section { Text("plex.dashboard.rankingsLimited").foregroundStyle(.secondary) }
            }
            Section {
                if let error = model.errors[.rankings] {
                    status(error, symbol: "exclamationmark.circle")
                    Button("common.actions.retry") { Task { await model.loadRankings(force: true) } }
                } else if model.loading.contains(.rankings) {
                    ProgressView("plex.dashboard.loadingRankings")
                } else if model.filteredTopTitles.isEmpty {
                    status(String(localized: "plex.dashboard.noHistory"), symbol: "chart.bar")
                } else {
                    ForEach(model.filteredTopTitles) { title in
                        Button { onSelect(title.media.groupKey) } label: {
                            HStack(spacing: 14) {
                                PlexDashboardPoster(path: title.media.thumb, repository: model.repository)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(title.media.title).font(.rowTitle).foregroundStyle(.primary)
                                    Text("plex.dashboard.plays \(title.plays)").foregroundStyle(.secondary)
                                    ForEach(title.accountIDs.sorted(), id: \.self) { id in
                                        PlexDashboardUserLabel(name: model.userName(id), url: model.userAvatar(id))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.padding(.vertical, 4)
                        }.buttonStyle(.plain)
                            .disabled(!title.media.canOpenDetail || title.media.groupKey.isEmpty)
                    }
                }
            } footer: { Text("plex.dashboard.rankingsExplanation") }
        }

        @ViewBuilder private var filterError: some View {
            if model.errors[.users] != nil || model.errors[.libraries] != nil {
                Section { Text("plex.dashboard.filtersUnavailable").font(.footnote).foregroundStyle(.secondary) }
            }
        }

        private func metric(
            _ title: LocalizedStringKey,
            points: [PlexDashboardPoint],
            unit: String,
            errorKey: PlexDashboardLoad,
            percentage: Bool,
        ) -> some View {
            Section {
                if let error = model.errors[errorKey] {
                    status(error, symbol: "chart.xyaxis.line")
                } else if model.loading.contains(errorKey), model.updatedAt == nil {
                    ProgressView()
                } else if points.isEmpty {
                    status(String(localized: "plex.dashboard.noSamples"), symbol: "chart.xyaxis.line")
                } else {
                    PlexMetricChart(points: points, unit: unit, percentage: percentage)
                        .padding(.vertical, 8)
                }
            } header: { Text(title) }
        }

        private func status(_ message: String, symbol: String) -> some View {
            Label(message, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct PlexDashboardUserLabel: View {
        let name: String
        let url: URL?
        @State private var loadedAvatar: (url: URL, image: Image)?

        var body: some View {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(.quaternary)
                    Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                    if let loadedAvatar, loadedAvatar.url == url {
                        loadedAvatar.image.resizable().scaledToFill()
                    }
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())
                .accessibilityHidden(true)
                Text(name)
            }
            .task(id: url) {
                guard let url, let image = await ArtworkResourceView.image(for: .url(url)),
                      !Task.isCancelled else { return }
                loadedAvatar = (url, image)
            }
        }
    }

    private struct PlexDashboardUserPicker: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: PlexDashboardViewModel
        @State private var query = ""

        private var users: [PlexDashboardUser] {
            model.selectableUsers.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        var body: some View {
            List {
                Button { select("") } label: {
                    HStack {
                        Label("plex.dashboard.allUsers", systemImage: "person.2")
                        Spacer()
                        if model.userID.isEmpty {
                            Image(systemName: "checkmark")
                        }
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(model.userID.isEmpty ? .isSelected : [])
                ForEach(users) { user in userButton(user) }
            }
            .navigationTitle("plex.dashboard.user")
            .searchable(text: $query)
            .overlay {
                if users.isEmpty, !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }

        private func userButton(_ user: PlexDashboardUser) -> some View {
            Button { select(user.id) } label: {
                HStack {
                    PlexDashboardUserLabel(name: user.name, url: model.userAvatar(user.id))
                    Spacer()
                    if model.userID == user.id {
                        Image(systemName: "checkmark")
                    }
                }.frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(model.userID == user.id ? .isSelected : [])
        }

        private func select(_ id: String) {
            model.userID = id
            dismiss()
        }
    }

    private struct PlexDashboardMediaRow: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let play: PlexDashboardPlay
        let repository: PlexDashboardRepository
        let user: String
        let avatarURL: URL?
        let live: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    PlexDashboardPoster(path: play.thumb, repository: repository)
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(play.title).font(.rowTitle).foregroundStyle(.primary)
                            if let subtitle = play.subtitle {
                                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        PlexDashboardUserLabel(name: user, url: avatarURL)
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !live, let date = play.viewedAt {
                            Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if live {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                    layout { playbackLabels }
                        .labelStyle(.titleAndIcon)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if let state = PlexDashboardFormatting.playbackState(play.state) {
                                Text(state)
                            }
                            Spacer(minLength: 8)
                            if let position = play.streamDetails.first(where: { $0.field == .position }) {
                                Text(position.value).monospacedDigit()
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        if let progress = play.progress {
                            ProgressView(value: progress).tint(.accentColor)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder private var playbackLabels: some View {
            if let player = play.player {
                Label(player, systemImage: "tv")
            }
            Label(decision, systemImage: play.decision == "transcode" ? "arrow.triangle.2.circlepath" : "play.circle")
        }

        private var decision: String {
            PlexDashboardFormatting.decision(play.decision) ?? String(localized: "plex.dashboard.directPlay")
        }
    }

    private struct PlexDashboardPoster: View {
        let path: String?
        let repository: PlexDashboardRepository

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                Image(systemName: "play.rectangle").foregroundStyle(.secondary)
                if let url = repository.artworkURL(path) {
                    ArtworkResourceView(resource: .url(url))
                }
            }
            .frame(width: 56, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
        }
    }

#endif
