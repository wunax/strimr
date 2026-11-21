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
                // A title from the previous server must not open after switching to another one.
                .onChange(of: server?.identity) {
                    detailTask?.cancel()
                    detailTask = nil
                }
        }

        /// Only the latest tap on the selected server opens a detail page, and nothing opens once the dashboard is
        /// gone.
        private func openDetail(_ key: String, on server: ServerIdentity) {
            guard !key.isEmpty, let services = registry.services(for: server) else { return }
            detailTask?.cancel()
            let generation = registry.generation
            detailTask = Task {
                do {
                    let media = try await services.detail.mediaItem(id: key)
                    guard !Task.isCancelled, generation == registry.generation, self.server?.identity == server
                    else { return }
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
            content
                .task { await model.loadFilters() }
                .toolbar {
                    #if os(macOS)
                        ToolbarItem(placement: .principal) {
                            tabPicker.pickerStyle(.segmented).fixedSize()
                        }
                    #endif
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
            #if os(macOS)
                .navigationSubtitle(serverName)
            #endif
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

        /// macOS shows the dashboard as a page of cards and history and top titles as tables, with the tab picker in
        /// the toolbar.
        @ViewBuilder private var content: some View {
            #if os(macOS)
                switch model.tab {
                case .dashboard: macDashboard
                case .history: PlexHistoryTable(model: model, onSelect: onSelect)
                case .topPlayed: PlexTopPlayedTable(model: model, onSelect: onSelect)
                }
            #else
                List {
                    Section {
                        if dynamicTypeSize.isAccessibilitySize {
                            tabPicker.pickerStyle(.menu)
                        } else {
                            // The segmented control has its own background, so it sits on the page as wide as the cards
                            // below.
                            tabPicker.pickerStyle(.segmented)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
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
            #endif
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
                if showsSessions {
                    ForEach(model.sessions) { play in
                        liveSession(play)
                    }
                } else {
                    sessionsStatus
                }
            } header: { Text("plex.dashboard.nowPlaying") } footer: { updatedFooter }

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
                activityContent
            } header: { Text("plex.dashboard.playHistory") } footer: {
                Text("plex.dashboard.recordedTime")
            }

            if !model.topUsers.isEmpty {
                Section("plex.dashboard.topUsers") {
                    ForEach(model.topUsers) { user in
                        topUserRow(user)
                    }
                }
            }
            filterError
        }

        @ViewBuilder private var activityContent: some View {
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
        }

        @ViewBuilder private var sessionsStatus: some View {
            if let error = model.errors[.sessions] {
                status(error, symbol: "wifi.exclamationmark")
            } else if model.loading.contains(.sessions), model.updatedAt == nil {
                ProgressView()
            } else if model.sessions.isEmpty {
                status(String(localized: "plex.dashboard.noStreams"), symbol: "play.rectangle")
            }
        }

        private var showsSessions: Bool {
            model.errors[.sessions] == nil && !model.sessions.isEmpty
        }

        @ViewBuilder private var updatedFooter: some View {
            if let updatedAt = model.updatedAt {
                Text("plex.dashboard.updated \(updatedAt.formatted(date: .omitted, time: .standard))")
            }
        }

        private func topUserRow(_ user: PlexDashboardTopUser) -> some View {
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

        #if os(macOS)
            private var macDashboard: some View {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        PlexDashboardMacSection("plex.dashboard.nowPlaying") {
                            if showsSessions {
                                LazyVGrid(columns: Self.columns(minimum: 340), alignment: .leading, spacing: 16) {
                                    ForEach(model.sessions) { play in
                                        liveSession(play).dashboardCard()
                                    }
                                }
                            } else {
                                sessionsStatus.dashboardCard()
                            }
                        } footer: { updatedFooter }

                        LazyVGrid(columns: Self.columns(minimum: 400), alignment: .leading, spacing: 28) {
                            PlexDashboardMacSection("plex.dashboard.bandwidth") {
                                metricContent(
                                    points: model.bandwidth,
                                    unit: "Mbps",
                                    errorKey: .bandwidth,
                                    percentage: false,
                                ).dashboardCard()
                            }
                            PlexDashboardMacSection("plex.dashboard.cpu") {
                                metricContent(points: model.cpu, unit: "%", errorKey: .resources, percentage: true)
                                    .dashboardCard()
                            }
                            PlexDashboardMacSection("plex.dashboard.memory") {
                                metricContent(points: model.memory, unit: "%", errorKey: .resources, percentage: true)
                                    .dashboardCard()
                            }
                        }

                        LazyVGrid(
                            columns: model.topUsers.isEmpty
                                ? [GridItem(.flexible(), alignment: .top)]
                                : Self.columns(minimum: 560),
                            alignment: .leading,
                            spacing: 28,
                        ) {
                            PlexDashboardMacSection("plex.dashboard.playHistory") {
                                VStack(alignment: .leading, spacing: 12) {
                                    periodPicker.fixedSize()
                                    activityContent
                                }.dashboardCard()
                            } footer: { Text("plex.dashboard.recordedTime") }
                            if !model.topUsers.isEmpty {
                                PlexDashboardMacSection("plex.dashboard.topUsers") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(Array(model.topUsers.enumerated()), id: \.element.id) { index, user in
                                            if index > 0 {
                                                Divider()
                                            }
                                            topUserRow(user)
                                        }
                                    }.dashboardCard()
                                }
                            }
                        }

                        if model.errors[.users] != nil || model.errors[.libraries] != nil {
                            Text("plex.dashboard.filtersUnavailable").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .dashboardPage()
                }
            }

            /// Cards fill the row and wrap onto the next one when the window gets narrower than the minimum. The
            /// minimums keep the three charts and the history and top users pair on one row each at the 1600 pt
            /// content width.
            private static func columns(minimum: CGFloat) -> [GridItem] {
                [GridItem(.adaptive(minimum: minimum), spacing: 16, alignment: .top)]
            }
        #endif

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
                } else if model.historyHasMore {
                    // A page can hold no usable rows while later pages still do.
                    Button("plex.dashboard.loadMore") { Task { await model.loadHistory(reset: false) } }
                        .frame(maxWidth: .infinity)
                } else if model.history.isEmpty {
                    status(String(localized: "plex.dashboard.noHistory"), symbol: "clock")
                }
            }
        }

        @ViewBuilder private var topPlayed: some View {
            Section {
                periodPicker
                mediaTypePicker
            }
            if model.rankingsIncomplete {
                Section { Text("plex.dashboard.rankingsLimited").foregroundStyle(.secondary) }
            }
            Section {
                if showsTopTitles {
                    ForEach(model.filteredTopTitles) { title in
                        topTitleButton(title)
                    }
                } else {
                    rankingsStatus
                }
            } footer: { Text("plex.dashboard.rankingsExplanation") }
        }

        private var mediaTypePicker: some View {
            Picker("plex.dashboard.mediaType", selection: $model.kind) {
                Text("plex.dashboard.allMedia").tag(PlexDashboardMediaKind?.none)
                ForEach(PlexDashboardMediaKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
        }

        private var showsTopTitles: Bool {
            model.errors[.rankings] == nil && !model.loading.contains(.rankings) && !model.filteredTopTitles.isEmpty
        }

        @ViewBuilder private var rankingsStatus: some View {
            if let error = model.errors[.rankings] {
                status(error, symbol: "exclamationmark.circle")
                Button("common.actions.retry") { Task { await model.loadRankings(force: true) } }
            } else if model.loading.contains(.rankings) {
                ProgressView("plex.dashboard.loadingRankings")
            } else if model.filteredTopTitles.isEmpty {
                status(String(localized: "plex.dashboard.noHistory"), symbol: "chart.bar")
            }
        }

        private func topTitleButton(_ title: PlexDashboardTopTitle) -> some View {
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
            }
            .buttonStyle(.plain)
            .disabled(!title.media.canOpenDetail || title.media.groupKey.isEmpty)
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
                metricContent(points: points, unit: unit, errorKey: errorKey, percentage: percentage)
            } header: { Text(title) }
        }

        @ViewBuilder private func metricContent(
            points: [PlexDashboardPoint],
            unit: String,
            errorKey: PlexDashboardLoad,
            percentage: Bool,
        ) -> some View {
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

        var body: some View {
            HStack(spacing: 8) {
                PlexDashboardAvatar(url: url)
                Text(name)
            }
        }
    }

    private struct PlexDashboardAvatar: View {
        let url: URL?
        @State private var loadedAvatar: (url: URL, image: Image)?

        var body: some View {
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

    #if os(macOS)
        /// History on macOS: one row per play, newest first, with the filters above the table.
        private struct PlexHistoryTable: View {
            @Bindable var model: PlexDashboardViewModel
            let onSelect: (String) -> Void
            @State private var selection: PlexDashboardPlay.ID?

            private var users: [PlexDashboardUser] {
                model.selectableUsers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }

            var body: some View {
                VStack(spacing: 0) {
                    PlexDashboardFilterBar {
                        Picker("plex.dashboard.user", selection: $model.userID) {
                            Text("plex.dashboard.allUsers").tag("")
                            ForEach(users) { Text($0.name).tag($0.id) }
                            // The active filter keeps its option even if the account drops out of the list.
                            if !model.userID.isEmpty, !users.contains(where: { $0.id == model.userID }) {
                                Text(model.userName(model.userID)).tag(model.userID)
                            }
                        }.fixedSize()
                        Picker("plex.dashboard.library", selection: $model.libraryID) {
                            Text("plex.dashboard.allLibraries").tag("")
                            ForEach(model.libraries) { Text($0.name).tag($0.id) }
                        }.fixedSize()
                        Picker("plex.dashboard.period", selection: $model.historyPeriod) {
                            ForEach(PlexDashboardPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.fixedSize()
                    } note: {
                        if model.errors[.users] != nil || model.errors[.libraries] != nil {
                            Text("plex.dashboard.filtersUnavailable")
                        }
                    }
                    Divider()
                    Table(model.history, selection: $selection) {
                        TableColumn("plex.dashboard.column.title") { play in
                            PlexDashboardTitleCell(
                                path: play.thumb,
                                title: play.title,
                                subtitle: play.subtitle,
                                repository: model.repository,
                            )
                        }
                        TableColumn("plex.dashboard.user") { play in
                            PlexDashboardUserLabel(
                                name: model.userName(play.accountID),
                                url: model.userAvatar(play.accountID),
                            )
                        }
                        .width(min: 120, ideal: 180, max: 260)
                        TableColumn("plex.dashboard.column.watched") { play in
                            if let date = play.viewedAt {
                                Text(date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .width(min: 140, ideal: 170, max: 220)
                    }
                    .contextMenu(forSelectionType: PlexDashboardPlay.ID.self) { ids in
                        if let play = openablePlay(ids) {
                            Button("media.quickActions.showDetails") { onSelect(play.ratingKey) }
                        }
                    } primaryAction: { ids in
                        if let play = openablePlay(ids) {
                            onSelect(play.ratingKey)
                        }
                    }
                    .overlay { emptyState }
                    footer
                }
            }

            /// Only a single row opens, so a double-click never picks one of several selected rows at random.
            private func openablePlay(_ ids: Set<PlexDashboardPlay.ID>) -> PlexDashboardPlay? {
                guard ids.count == 1, let play = model.history.first(where: { ids.contains($0.id) }),
                      play.canOpenDetail else { return nil }
                return play
            }

            @ViewBuilder private var emptyState: some View {
                if model.history.isEmpty {
                    if let error = model.errors[.history] {
                        ContentUnavailableView {
                            Label(error, systemImage: "exclamationmark.circle")
                        } actions: {
                            Button("common.actions.retry") { Task { await model.loadHistory(reset: true) } }
                        }
                    } else if model.loading.contains(.history) {
                        ProgressView()
                    } else {
                        ContentUnavailableView("plex.dashboard.noHistory", systemImage: "clock")
                    }
                }
            }

            /// Paging stays an explicit action, as on iOS, so scrolling never starts a request on its own.
            @ViewBuilder private var footer: some View {
                // Load more stays reachable when a page had no usable rows but the server reports more.
                if model.historyHasMore
                    || (!model.history.isEmpty && (model.errors[.history] != nil || model.loading.contains(.history)))
                {
                    Divider()
                    HStack(spacing: 12) {
                        if let error = model.errors[.history] {
                            Text(error).foregroundStyle(.secondary)
                            Button("common.actions.retry") { Task { await model.loadHistory(reset: false) } }
                        } else if model.loading.contains(.history) {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("plex.dashboard.loadMore") { Task { await model.loadHistory(reset: false) } }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
        }

        /// Top played on macOS: a ranked table with a quiet bar that compares each title with the most played one.
        private struct PlexTopPlayedTable: View {
            @Bindable var model: PlexDashboardViewModel
            let onSelect: (String) -> Void
            @State private var selection: PlexDashboardTopTitle.ID?

            var body: some View {
                let titles = model.filteredTopTitles
                let ranks = Dictionary(uniqueKeysWithValues: titles.enumerated().map { ($1.id, $0 + 1) })
                let mostPlays = max(1, titles.first?.plays ?? 1)
                VStack(spacing: 0) {
                    PlexDashboardFilterBar {
                        Picker("plex.dashboard.period", selection: $model.period) {
                            ForEach(PlexDashboardPeriod.allCases.filter { $0 != .all }, id: \.self) { period in
                                Text(period.title).tag(period)
                            }
                        }.fixedSize()
                        Picker("plex.dashboard.mediaType", selection: $model.kind) {
                            Text("plex.dashboard.allMedia").tag(PlexDashboardMediaKind?.none)
                            ForEach(PlexDashboardMediaKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                        }.fixedSize()
                    } note: {
                        if model.rankingsIncomplete {
                            Text("plex.dashboard.rankingsLimited")
                        }
                    }
                    Divider()
                    Table(model.loading.contains(.rankings) ? [] : titles, selection: $selection) {
                        TableColumn("plex.dashboard.column.rank") { title in
                            Text(ranks[title.id] ?? 0, format: .number)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .width(44)
                        TableColumn("plex.dashboard.column.title") { title in
                            PlexDashboardTitleCell(
                                path: title.media.thumb,
                                title: title.media.title,
                                subtitle: title.media.kind.title,
                                repository: model.repository,
                            )
                        }
                        .width(min: 220, ideal: 320, max: 420)
                        TableColumn("plex.dashboard.column.plays") { title in
                            HStack(spacing: 10) {
                                Text(title.plays, format: .number)
                                    .monospacedDigit()
                                    .frame(minWidth: 24, alignment: .trailing)
                                ProgressView(value: Double(title.plays), total: Double(mostPlays))
                                    .accessibilityHidden(true)
                            }
                        }
                        .width(min: 160, ideal: 260, max: 320)
                        TableColumn("plex.dashboard.column.users") { title in
                            PlexDashboardAvatarStack(model: model, accountIDs: title.accountIDs.sorted())
                        }
                        .width(min: 120, ideal: 200)
                    }
                    .contextMenu(forSelectionType: PlexDashboardTopTitle.ID.self) { ids in
                        if let key = openableKey(ids, in: titles) {
                            Button("media.quickActions.showDetails") { onSelect(key) }
                        }
                    } primaryAction: { ids in
                        if let key = openableKey(ids, in: titles) {
                            onSelect(key)
                        }
                    }
                    .overlay { emptyState(isEmpty: titles.isEmpty) }
                    Divider()
                    Text("plex.dashboard.rankingsExplanation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }

            private func openableKey(
                _ ids: Set<PlexDashboardTopTitle.ID>,
                in titles: [PlexDashboardTopTitle],
            ) -> String? {
                guard ids.count == 1, let title = titles.first(where: { ids.contains($0.id) }),
                      title.media.canOpenDetail, !title.media.groupKey.isEmpty else { return nil }
                return title.media.groupKey
            }

            @ViewBuilder private func emptyState(isEmpty: Bool) -> some View {
                if let error = model.errors[.rankings] {
                    ContentUnavailableView {
                        Label(error, systemImage: "exclamationmark.circle")
                    } actions: {
                        Button("common.actions.retry") { Task { await model.loadRankings(force: true) } }
                    }
                } else if model.loading.contains(.rankings) {
                    ProgressView("plex.dashboard.loadingRankings")
                } else if isEmpty {
                    ContentUnavailableView("plex.dashboard.noHistory", systemImage: "chart.bar")
                }
            }
        }

        /// The filters of a table, in one row that wraps under each other when the window is narrow.
        private struct PlexDashboardFilterBar<Filters: View, Note: View>: View {
            let filters: Filters
            let note: Note

            init(@ViewBuilder filters: () -> Filters, @ViewBuilder note: () -> Note) {
                self.filters = filters()
                self.note = note()
            }

            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) { filters }
                        VStack(alignment: .leading, spacing: 8) { filters }
                    }
                    note.font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }

        /// Poster, title and one line of context, the same height in every row.
        private struct PlexDashboardTitleCell: View {
            let path: String?
            let title: String
            let subtitle: String?
            let repository: PlexDashboardRepository

            var body: some View {
                HStack(spacing: 12) {
                    PlexDashboardPoster(path: path, repository: repository, width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).lineLimit(1)
                        Text(subtitle ?? " ").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
            }
        }

        /// Overlapping avatars keep every row one line high; the names are in the tooltip and for VoiceOver.
        private struct PlexDashboardAvatarStack: View {
            let model: PlexDashboardViewModel
            let accountIDs: [String]
            private let visibleCount = 5

            private var names: String {
                accountIDs.map { model.userName($0) }.formatted(.list(type: .and))
            }

            var body: some View {
                HStack(spacing: -6) {
                    ForEach(accountIDs.prefix(visibleCount), id: \.self) { id in
                        PlexDashboardAvatar(url: model.userAvatar(id))
                            .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    }
                    if accountIDs.count > visibleCount {
                        Text("+\(accountIDs.count - visibleCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 10)
                    }
                }
                .help(names)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(names)
            }
        }

        /// A titled group of cards on the macOS dashboard, with the same header and footer text as the iOS list.
        private struct PlexDashboardMacSection<Content: View, Footer: View>: View {
            let title: LocalizedStringKey
            let content: Content
            let footer: Footer

            init(
                _ title: LocalizedStringKey,
                @ViewBuilder content: () -> Content,
                @ViewBuilder footer: () -> Footer = { EmptyView() },
            ) {
                self.title = title
                self.content = content()
                self.footer = footer()
            }

            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                    content
                    footer.font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        /// The default macOS style lays label and value out like a form and centers them inside a card.
        private struct PlexDashboardRowStyle: LabeledContentStyle {
            func makeBody(configuration: Configuration) -> some View {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    configuration.label
                    Spacer(minLength: 12)
                    configuration.content
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }

        private extension View {
            func dashboardPage() -> some View {
                padding(24)
                    .frame(maxWidth: 1600, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }

            func dashboardCard() -> some View {
                labeledContentStyle(PlexDashboardRowStyle())
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quinary, in: .rect(cornerRadius: 12))
            }
        }
    #endif

    private struct PlexDashboardPoster: View {
        let path: String?
        let repository: PlexDashboardRepository
        var width: CGFloat = 56

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius).fill(.quaternary)
                Image(systemName: "play.rectangle").foregroundStyle(.secondary)
                if let url = repository.artworkURL(path) {
                    ArtworkResourceView(resource: .url(url))
                }
            }
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
        }

        private var cornerRadius: CGFloat {
            width < 40 ? 4 : 8
        }
    }

#endif
