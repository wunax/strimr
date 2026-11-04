import Foundation
import Observation

@MainActor
@Observable
final class LiveTVStore {
    enum Availability: Equatable {
        case unknown
        case unavailable
        case available
    }

    private(set) var availability: Availability = .unknown
    private(set) var channels: [LiveTVChannel] = []
    private(set) var programs: [LiveTVProgram] = []
    private(set) var onNowSections: [LiveTVOnNowSection] = []
    private(set) var upcomingRecordings: [DVRRecording] = []
    private(set) var recordingRules: [DVRRecordingRule] = []
    private(set) var completedRecordings: [DVRRecording] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var guideStart = Date()
    private(set) var guideEnd = Date()
    private(set) var recentChannelKeys: [String] = []
    /// The channel the player last left, and when, so the guide can bring it back into view.
    private(set) var lastPlayedChannel: LiveTVChannelIdentity?
    private(set) var playbackEndedAt: Date?

    @ObservationIgnored let service: any MediaLiveTVService
    @ObservationIgnored private let recentChannels: LiveTVRecentChannels?
    @ObservationIgnored private var availabilityTask: Task<Bool, Never>?
    @ObservationIgnored private var contentTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var didReportAvailabilityError = false
    @ObservationIgnored private var isExtendingGuide = false

    init(service: any MediaLiveTVService, recentChannels: LiveTVRecentChannels? = nil) {
        self.service = service
        self.recentChannels = recentChannels
        recentChannelKeys = recentChannels?.channelKeys ?? []
    }

    func shelves(now: Date = Date()) -> LiveTVShelves {
        LiveTVShelves(
            channels: channels,
            programs: programs,
            onNowSections: onNowSections,
            recordings: upcomingRecordings,
            recentChannelKeys: recentChannelKeys,
            now: now,
        )
    }

    func channel(for identity: LiveTVChannelIdentity) -> LiveTVChannel? {
        channels.first { $0.identity == identity }
    }

    func currentProgram(on channel: LiveTVChannelIdentity, at date: Date = Date()) -> LiveTVProgram? {
        programs.first { $0.channelIdentity == channel && $0.isAiring(at: date) }
    }

    func nextProgram(on channel: LiveTVChannelIdentity, after date: Date = Date()) -> LiveTVProgram? {
        programs
            .filter { $0.channelIdentity == channel && $0.startDate >= date }
            .min { $0.startDate < $1.startDate }
    }

    func notePlaybackEnded(on channel: LiveTVChannelIdentity) {
        lastPlayedChannel = channel
        playbackEndedAt = Date()
    }

    func recordWatched(_ channel: LiveTVChannelIdentity) {
        guard let recentChannels else { return }
        recentChannels.record(channel)
        recentChannelKeys = recentChannels.channelKeys
    }

    var isAvailable: Bool {
        availability == .available
    }

    var dvr: (any MediaDVRService)? {
        service.dvr
    }

    @discardableResult
    func refreshAvailability(force: Bool = false) async -> Bool {
        if !force, availability != .unknown {
            return availability == .available
        }
        if let availabilityTask {
            return await availabilityTask.value
        }
        let previous = availability
        let task = Task { @MainActor [service] in
            do {
                let available = try await service.isAvailable()
                guard !Task.isCancelled else { return previous == .available }
                availability = available ? .available : .unavailable
                if !available {
                    channels = []
                    programs = []
                    onNowSections = []
                }
                return available
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return previous == .available }
                availability = .unavailable
                if !didReportAvailabilityError {
                    didReportAvailabilityError = true
                    LiveTVErrorReporting.capture(error)
                }
                return false
            }
        }
        availabilityTask = task
        let value = await task.value
        availabilityTask = nil
        return value
    }

    func load(start: Date? = nil, force: Bool = false) async {
        guard await refreshAvailability(force: force) else { return }
        if let contentTask, !force {
            await contentTask.value
            return
        }
        if force {
            contentTask?.cancel()
        }
        generation += 1
        let loadGeneration = generation
        let range = Self.guideRange(containing: start ?? Date())
        isLoading = channels.isEmpty
        errorMessage = nil

        let task = Task { @MainActor [service] in
            do {
                async let loadedChannels = service.channels()
                async let loadedPrograms = service.programs(from: range.start, to: range.end)
                async let loadedOnNow = service.onNow()
                let values = try await (loadedChannels, loadedPrograms, loadedOnNow)
                guard !Task.isCancelled, loadGeneration == generation else { return }
                channels = values.0
                if values.0.isEmpty {
                    availability = .unavailable
                }
                programs = values.1
                onNowSections = values.2
                guideStart = range.start
                guideEnd = range.end
                isLoading = false
                await loadDVR(generation: loadGeneration)
            } catch {
                guard !Task.isCancelled, !error.isCancellation, loadGeneration == generation else { return }
                LiveTVErrorReporting.capture(error)
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
        contentTask = task
        await task.value
        if loadGeneration == generation {
            contentTask = nil
        }
    }

    func guideCovers(_ date: Date) -> Bool {
        date >= guideStart && date < guideEnd
    }

    func shiftGuide(hours: Int) async {
        await load(start: guideStart.addingTimeInterval(TimeInterval(hours * 3600)), force: true)
    }

    /// Loads the next block of the guide past one of its edges and keeps what is already loaded.
    func extendGuide(forward: Bool) async {
        guard !isExtendingGuide, !channels.isEmpty else { return }
        isExtendingGuide = true
        defer { isExtendingGuide = false }
        let loadGeneration = generation
        let start = forward ? guideEnd : guideStart.addingTimeInterval(-Self.guideBlock)
        let end = forward ? guideEnd.addingTimeInterval(Self.guideBlock) : guideStart
        do {
            let loaded = try await service.programs(from: start, to: end)
            guard !Task.isCancelled, loadGeneration == generation else { return }
            programs = Self.merging(programs, loaded)
            if forward {
                guideEnd = end
            } else {
                guideStart = start
            }
            applyRecordingState(upcomingRecordings)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            LiveTVErrorReporting.capture(error)
        }
    }

    static func merging(_ current: [LiveTVProgram], _ loaded: [LiveTVProgram]) -> [LiveTVProgram] {
        var seen = Set(current.map(\.identity))
        return (current + loaded.filter { seen.insert($0.identity).inserted })
            .sorted { $0.startDate < $1.startDate }
    }

    /// Start of the guide for a day: now for today, the morning for the days after.
    static func guideStart(forDay day: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) {
            return now
        }
        let startOfDay = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: 6, to: startOfDay) ?? startOfDay
    }

    private static let guideBlock: TimeInterval = 6 * 3600

    func jumpToNow() async {
        await load(start: Date(), force: true)
    }

    func toggleFavorite(_ channel: LiveTVChannel) async {
        do {
            try await service.setFavorite(!channel.isFavorite, channel: channel)
            channels = channels.map { item in
                guard item.identity == channel.identity else { return item }
                var item = item
                item.isFavorite.toggle()
                return item
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            LiveTVErrorReporting.capture(error)
            errorMessage = error.localizedDescription
        }
    }

    func reorderFavorites(_ favorites: [LiveTVChannel]) async throws {
        try await service.reorderFavorites(favorites)
        let favoriteIDs = favorites.map(\.identity)
        let order = Dictionary(uniqueKeysWithValues: favoriteIDs.enumerated().map { ($1, $0) })
        channels.sort { lhs, rhs in
            switch (order[lhs.id], order[rhs.id]) {
            case let (a?, b?): a < b
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
        }
    }

    /// Schedules a recording; without explicit values it takes the server's defaults for the program.
    func record(
        _ program: LiveTVProgram,
        series: Bool,
        libraryID: String? = nil,
        options: [String: String]? = nil,
    ) async throws {
        guard let dvr else { return }
        var libraryID = libraryID
        var options = options
        if options == nil {
            let template = try await dvr.recordingTemplate(for: program)
            let mode = template.template(for: series ? .series : .single)
            libraryID = libraryID ?? mode?.defaultLibraryID
            options = Dictionary(
                (mode?.options ?? []).map { ($0.id, $0.defaultValue) },
                uniquingKeysWith: { first, _ in first },
            )
        }
        try await dvr.schedule(DVRRecordingRequest(
            program: program,
            recordsSeries: series,
            targetLibraryID: libraryID,
            options: options ?? [:],
        ))
        await refreshDVR()
    }

    func cancelRecording(id: String) async throws {
        guard let dvr, !id.isEmpty else { return }
        try await dvr.cancel(recordingID: id)
        await refreshAfterRecordingRemoval()
    }

    func deleteRule(id: String) async throws {
        guard let dvr, !id.isEmpty else { return }
        try await dvr.delete(ruleID: id)
        await refreshAfterRecordingRemoval()
    }

    func refreshDVR() async {
        generation += 1
        await loadDVR(generation: generation)
    }

    /// Only the server knows which programs a removal affects: a rule covers many, and a program can carry a
    /// recording that is missing from the upcoming list. The loaded range is kept, including what the guide extended.
    private func refreshAfterRecordingRemoval() async {
        generation += 1
        let loadGeneration = generation
        do {
            async let loadedPrograms = service.programs(from: guideStart, to: guideEnd)
            async let loadedOnNow = service.onNow()
            let values = try await (loadedPrograms, loadedOnNow)
            guard !Task.isCancelled, loadGeneration == generation else { return }
            programs = values.0
            onNowSections = values.1
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            LiveTVErrorReporting.capture(error)
        }
        await loadDVR(generation: loadGeneration)
    }

    private func loadDVR(generation loadGeneration: Int) async {
        guard let dvr = service.dvr else {
            upcomingRecordings = []
            recordingRules = []
            completedRecordings = []
            return
        }
        do {
            async let upcoming = dvr.upcomingRecordings()
            async let rules = dvr.recordingRules()
            async let completed = dvr.supportsCompletedRecordings ? dvr.completedRecordings() : []
            let values = try await (upcoming, rules, completed)
            guard !Task.isCancelled, loadGeneration == generation else { return }
            upcomingRecordings = values.0
            recordingRules = values.1
            completedRecordings = values.2
            applyRecordingState(values.0)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            LiveTVErrorReporting.capture(error)
            errorMessage = error.localizedDescription
        }
    }

    private func applyRecordingState(_ recordings: [DVRRecording]) {
        var recordingsByProgramID: [String: DVRRecording] = [:]
        for recording in recordings {
            guard let programID = recording.programID else { continue }
            if recordingsByProgramID[programID]?.status != .recording || recording.status == .recording {
                recordingsByProgramID[programID] = recording
            }
        }

        func updated(_ program: LiveTVProgram) -> LiveTVProgram {
            var program = program
            if let recording = recordingsByProgramID[program.id] {
                program.recordingID = recording.id
                program.recordingStatus = recording.status
            } else if program.recordingStatus == nil, program.recordingID != nil || program.seriesRecordingID != nil {
                program.recordingStatus = .scheduled
            }
            return program
        }

        programs = programs.map(updated)
        onNowSections = onNowSections.map { section in
            var section = section
            section.programs = section.programs.map(updated)
            return section
        }
    }

    private static func guideRange(containing date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = (components.minute ?? 0) >= 30 ? 30 : 0
        var aligned = components
        aligned.minute = minute
        aligned.second = 0
        let start = calendar.date(from: aligned)!.addingTimeInterval(-3600)
        return (start, start.addingTimeInterval(6 * 3600))
    }
}
