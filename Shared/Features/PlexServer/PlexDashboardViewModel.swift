#if os(iOS) || os(macOS)
    import Foundation
    import Observation

    @MainActor
    @Observable
    final class PlexDashboardViewModel {
        let repository: PlexDashboardRepository
        var tab: PlexDashboardTab = .dashboard
        var period: PlexDashboardPeriod = .week
        var historyPeriod: PlexDashboardPeriod = .all
        var userID = ""
        var libraryID = ""
        var kind: PlexDashboardMediaKind?
        private(set) var users: [PlexDashboardUser] = []
        private(set) var libraries: [PlexDashboardLibrary] = []
        private(set) var sessions: [PlexDashboardPlay] = []
        private(set) var bandwidth: [PlexDashboardPoint] = []
        private(set) var cpu: [PlexDashboardPoint] = []
        private(set) var memory: [PlexDashboardPoint] = []
        private(set) var activity: [PlexDashboardActivity] = []
        private(set) var history: [PlexDashboardPlay] = []
        private(set) var topTitles: [PlexDashboardTopTitle] = []
        private(set) var errors: [PlexDashboardLoad: String] = [:]
        private(set) var loading: Set<PlexDashboardLoad> = []
        private(set) var historyHasMore = false
        private(set) var rankingsIncomplete = false
        private(set) var updatedAt: Date?
        @ObservationIgnored private var historyOffset = 0
        @ObservationIgnored private var historyGeneration = UUID()
        @ObservationIgnored private var rankingGeneration = UUID()
        @ObservationIgnored private var rankingsPeriod: PlexDashboardPeriod?
        @ObservationIgnored private var requestGenerations: [PlexDashboardLoad: UUID] = [:]

        init(repository: PlexDashboardRepository) {
            self.repository = repository
        }

        var selectableUsers: [PlexDashboardUser] {
            let namedUsers = users.filter(\.hasName)
            let liveIDs = Set(sessions.compactMap(\.accountID))
            let groups = Dictionary(grouping: namedUsers) {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            return namedUsers.filter { user in
                guard let peers = groups[user.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()],
                      peers.count > 1 else { return true }
                let current = peers.filter { $0.isCurrentAccount || liveIDs.contains($0.id) }
                // Only suppress an old duplicate when exactly one account is confirmed current.
                return current.count != 1 || current[0].id == user.id
            }
        }

        var historyFilterID: String {
            "\(historyPeriod.rawValue)|\(userID)|\(libraryID)"
        }

        var activityPoints: [PlexDashboardPoint] {
            var values: [String: PlexDashboardPoint] = [:]
            for row in activity {
                let day = Calendar.current.startOfDay(for: row.date)
                let key = "\(day.timeIntervalSince1970)|\(row.kind.rawValue)"
                values[key] = .init(
                    date: day,
                    series: row.kind.title,
                    value: (values[key]?.value ?? 0) + row.duration / 3600,
                )
            }
            return values.values.sorted { $0.date < $1.date }
        }

        var topUsers: [PlexDashboardTopUser] {
            Dictionary(grouping: activity, by: \.accountID).map { id, rows in
                PlexDashboardTopUser(
                    id: id,
                    plays: rows.reduce(0) { $0 + $1.plays },
                    duration: rows.reduce(0) { $0 + $1.duration },
                    breakdown: Dictionary(grouping: rows, by: \.kind).mapValues { $0.reduce(0) { $0 + $1.duration } },
                )
            }.sorted { $0.duration == $1.duration ? $0.id < $1.id : $0.duration > $1.duration }
        }

        var filteredTopTitles: [PlexDashboardTopTitle] {
            topTitles.filter { kind == nil || $0.media.kind == kind }
        }

        func userName(_ id: String?) -> String {
            users.first { $0.id == id }?.name ?? String(localized: "plex.dashboard.unknownUser")
        }

        func userAvatar(_ id: String?) -> URL? {
            repository.avatarURL(users.first { $0.id == id }?.thumb)
        }

        func loadFilters() async {
            async let userRequest: Void = load(
                .users,
                fetch: { try await self.repository.users() },
                apply: { self.users = $0 },
            )
            async let libraryRequest: Void = load(
                .libraries,
                fetch: { try await self.repository.libraries() },
                apply: { self.libraries = $0 },
            )
            _ = await (userRequest, libraryRequest)
            // The server's account list shows first; names and avatars from plex.tv fill in afterwards.
            let generation = requestGenerations[.users]
            guard !Task.isCancelled, errors[.users] == nil, !users.isEmpty else { return }
            let resolvedUsers = await repository.resolvedUsers(users)
            guard !Task.isCancelled, requestGenerations[.users] == generation else { return }
            users = resolvedUsers
        }

        func poll() async {
            while !Task.isCancelled {
                await refreshLive()
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
            }
        }

        /// Overlapping refreshes, such as a poll and a pull to refresh, are fine: only the latest result is applied.
        func refreshLive() async {
            async let sessions: Void = load(
                .sessions,
                fetch: { try await self.repository.sessions() },
                apply: { self.sessions = $0 },
            )
            async let bandwidth: Void = load(
                .bandwidth,
                fetch: { try await self.repository.bandwidth() },
                apply: { self.bandwidth = $0 },
            )
            async let resources: Void = load(
                .resources,
                fetch: { try await self.repository.resources() },
                apply: { result in
                    self.cpu = result.cpu
                    self.memory = result.memory
                },
            )
            _ = await (sessions, bandwidth, resources)
            if !Task.isCancelled, errors[.sessions] == nil {
                updatedAt = Date()
            }
        }

        func loadActivity() async {
            let start = period.start ?? .distantPast
            activity = []
            await load(
                .activity,
                fetch: { try await self.repository.activity(start: start) },
                apply: { self.activity = $0 },
            )
        }

        func loadHistory(reset: Bool) async {
            if reset {
                historyGeneration = UUID()
                historyOffset = 0
                history = []
                historyHasMore = false
            } else if loading.contains(.history) {
                return
            }
            let generation = historyGeneration
            let filter = historyFilterID
            loading.insert(.history)
            errors[.history] = nil
            defer {
                if generation == historyGeneration {
                    loading.remove(.history)
                }
            }
            do {
                let page = try await repository.history(
                    start: historyPeriod.start,
                    accountID: userID.isEmpty ? nil : userID,
                    libraryID: libraryID.isEmpty ? nil : libraryID,
                    offset: historyOffset,
                )
                guard !Task.isCancelled, generation == historyGeneration, filter == historyFilterID else { return }
                var seen = Set(history.map(\.id))
                history += page.items.filter { seen.insert($0.id).inserted }
                historyOffset = page.nextOffset
                historyHasMore = page.hasMore
            } catch {
                guard !Task.isCancelled, generation == historyGeneration else { return }
                errors[.history] = PlexDashboardFormatting.error(error)
            }
        }

        /// Counting plays pages through the whole history of the period, so a finished count is kept until the period
        /// changes or the user refreshes.
        func loadRankings(force: Bool = false) async {
            let selectedPeriod = period
            guard force || rankingsPeriod != selectedPeriod else { return }
            let generation = UUID()
            rankingGeneration = generation
            rankingsPeriod = nil
            topTitles = []
            rankingsIncomplete = false
            loading.insert(.rankings)
            errors[.rankings] = nil
            defer {
                if generation == rankingGeneration {
                    loading.remove(.rankings)
                }
            }
            do {
                var items: [PlexDashboardPlay] = []
                var seen: Set<String> = []
                var offset = 0
                var hasMore = true
                while hasMore, offset < 10000 {
                    try Task.checkCancellation()
                    let page = try await repository.history(
                        start: selectedPeriod.start,
                        accountID: nil,
                        libraryID: nil,
                        offset: offset,
                    )
                    guard generation == rankingGeneration else { return }
                    items += page.items.filter { seen.insert($0.id).inserted }
                    offset = page.nextOffset
                    hasMore = page.hasMore
                }
                try Task.checkCancellation()
                guard generation == rankingGeneration else { return }
                rankingsIncomplete = hasMore
                rankingsPeriod = selectedPeriod
                topTitles = Dictionary(
                    grouping: items,
                    by: { "\($0.kind.rawValue)|\($0.groupKey.isEmpty ? $0.id : $0.groupKey)" },
                )
                .compactMap { id, plays in
                    guard let media = plays.first else { return nil }
                    return PlexDashboardTopTitle(
                        id: id,
                        media: media,
                        plays: plays.count,
                        accountIDs: Set(plays.compactMap(\.accountID)),
                    )
                }.sorted { $0.plays == $1.plays ? $0.media.title < $1.media.title : $0.plays > $1.plays }
            } catch {
                guard !Task.isCancelled, generation == rankingGeneration else { return }
                errors[.rankings] = PlexDashboardFormatting.error(error)
            }
        }

        /// Runs `fetch` and applies its result only if no newer load of the same part started in the meantime.
        private func load<Value>(
            _ key: PlexDashboardLoad,
            fetch: @MainActor () async throws -> Value,
            apply: @MainActor (Value) -> Void,
        ) async {
            let generation = UUID()
            requestGenerations[key] = generation
            loading.insert(key)
            defer {
                if requestGenerations[key] == generation {
                    loading.remove(key)
                }
            }
            do {
                let value = try await fetch()
                guard !Task.isCancelled, requestGenerations[key] == generation else { return }
                apply(value)
                errors[key] = nil
            } catch {
                guard !Task.isCancelled, requestGenerations[key] == generation else { return }
                errors[key] = PlexDashboardFormatting.error(error)
            }
        }
    }

#endif
