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

    @ObservationIgnored let service: any MediaLiveTVService
    @ObservationIgnored private var availabilityTask: Task<Bool, Never>?
    @ObservationIgnored private var contentTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(service: any MediaLiveTVService) {
        self.service = service
    }

    var isAvailable: Bool { availability == .available }
    var dvr: (any MediaDVRService)? { service.dvr }

    @discardableResult
    func refreshAvailability() async -> Bool {
        if let availabilityTask { return await availabilityTask.value }
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
                LiveTVErrorReporting.capture(error)
                // A transient failure must not erase a previously working destination.
                if previous == .unknown { availability = .unavailable }
                return previous == .available
            }
        }
        availabilityTask = task
        let value = await task.value
        availabilityTask = nil
        return value
    }

    func load(start: Date? = nil, force: Bool = false) async {
        guard await refreshAvailability() else { return }
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
        if loadGeneration == generation { contentTask = nil }
    }

    func shiftGuide(hours: Int) async {
        await load(start: guideStart.addingTimeInterval(TimeInterval(hours * 3600)), force: true)
    }

    func jumpToNow() async {
        await load(start: Date(), force: true)
    }

    func toggleFavorite(_ channel: LiveTVChannel) async {
        do {
            try await service.setFavorite(!channel.isFavorite, channel: channel)
            channels = channels.map { item in
                guard item.id == channel.id else { return item }
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
        let favoriteIDs = favorites.map(\.id)
        let order = Dictionary(uniqueKeysWithValues: favoriteIDs.enumerated().map { ($1, $0) })
        channels.sort { lhs, rhs in
            switch (order[lhs.id], order[rhs.id]) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
        }
    }

    func refreshDVR() async {
        generation += 1
        await loadDVR(generation: generation)
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
