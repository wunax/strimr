import Foundation
import Observation

@MainActor
@Observable
final class SeerrMediaRequestViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let permissionService: SeerrPermissionService

    var media: SeerrMedia
    var selectedRequestType: SeerrMediaRequestType?
    var selectedSeasons: Set<Int> = []
    var isLoadingServices = false
    var isSubmitting = false
    var errorMessage: String?
    var servicesErrorMessage: String?
    var isShowingError = false
    var didComplete = false

    var radarrServers: [SeerrRadarrServer] = []
    var sonarrServers: [SeerrSonarrServer] = []
    var serviceProfiles: [SeerrServiceProfile] = []
    var serviceRootFolders: [SeerrServiceRootFolder] = []
    var serviceTags: [SeerrServiceTag] = []
    var selectedServerId: Int?
    var selectedProfileId: Int?
    var selectedRootFolder: String?
    var selectedTags: [Int] = []

    private var loadedRequestType: SeerrMediaRequestType?
    private var hasManualSeasonSelection = false

    init(media: SeerrMedia, store: SeerrStore, session: URLSession = .shared) {
        self.media = media
        self.store = store
        self.session = session
        permissionService = SeerrPermissionService()
        if requestTypeOptions.count == 1 {
            selectedRequestType = requestTypeOptions.first
        }
        seedSelectedSeasonsIfNeeded()
    }

    var isTV: Bool {
        media.mediaType == .tv
    }

    var isMovie: Bool {
        media.mediaType == .movie
    }

    var isEditing: Bool {
        existingRequest != nil
    }

    var existingRequest: SeerrRequest? {
        SeerrMediaRequestAvailability.pendingRequest(in: media, for: store.user)
    }

    var requestTypeOptions: [SeerrMediaRequestType] {
        var options: [SeerrMediaRequestType] = []
        if canRequestStandard {
            options.append(.standard)
        }
        if canRequest4K {
            options.append(.fourK)
        }
        return options
    }

    var requiresRequestTypeSelection: Bool {
        requestTypeOptions.count > 1
    }

    var preferredRequestType: SeerrMediaRequestType? {
        guard let existingRequest else { return nil }
        return existingRequest.is4k == true ? .fourK : .standard
    }

    var seasons: [SeerrSeason] {
        media.seasons?.filter { $0.seasonNumber != nil } ?? []
    }

    var requestableSeasons: [SeerrSeason] {
        guard let requestType = selectedRequestType else { return [] }
        return SeerrMediaRequestAvailability.requestableSeasons(media: media, is4k: requestType.is4k)
    }

    var canSubmit: Bool {
        guard selectedRequestType != nil else { return false }
        guard servicesErrorMessage == nil else { return false }
        if isTV, selectedSeasons.isEmpty {
            return false
        }
        if requiresAdvancedConfiguration {
            guard selectedServerId != nil, selectedProfileId != nil, selectedRootFolder != nil else {
                return false
            }
        }
        return true
    }

    var submitButtonKey: String {
        if isEditing {
            return "seerr.request.action.update"
        }
        return "seerr.request.action.submit"
    }

    var sheetTitleKey: String {
        if isEditing {
            return "seerr.request.title.modify"
        }
        return "seerr.request.title"
    }

    var shouldShowServerPicker: Bool {
        requiresAdvancedConfiguration && availableServers.count > 1
    }

    var shouldShowRootFolderPicker: Bool {
        requiresAdvancedConfiguration && serviceRootFolders.count > 1
    }

    var shouldShowProfilePicker: Bool {
        requiresAdvancedConfiguration && serviceProfiles.count > 1
    }

    var availableServers: [SeerrServiceServerOption] {
        if isMovie {
            return radarrServers.map { SeerrServiceServerOption(id: $0.id, name: $0.name ?? "", isDefault: $0.isDefault ?? false) }
        }
        return sonarrServers.map { SeerrServiceServerOption(id: $0.id, name: $0.name ?? "", isDefault: $0.isDefault ?? false) }
    }

    func selectRequestType(_ type: SeerrMediaRequestType) {
        guard selectedRequestType != type else { return }
        selectedRequestType = type
        resetServiceSelection()
        hasManualSeasonSelection = false
        seedSelectedSeasonsIfNeeded()
    }

    func seasonAvailabilityBadge(for season: SeerrSeason) -> SeerrSeasonAvailabilityBadge? {
        guard let seasonNumber = season.seasonNumber, let requestType = selectedRequestType else { return nil }
        return SeerrMediaRequestAvailability.seasonAvailabilityBadge(
            media: media,
            seasonNumber: seasonNumber,
            is4k: requestType.is4k,
        )
    }

    func isSeasonSelectable(_ seasonNumber: Int) -> Bool {
        guard let requestType = selectedRequestType else { return false }
        guard allowsPartialRequests else { return false }
        let requestable = SeerrMediaRequestAvailability.isSeasonRequestable(
            media: media,
            seasonNumber: seasonNumber,
            is4k: requestType.is4k,
        )
        if requestable {
            return true
        }
        return isEditing && existingRequestSeasonNumbers.contains(seasonNumber)
    }

    func toggleSeason(_ seasonNumber: Int, isSelected: Bool) {
        guard allowsPartialRequests else { return }
        hasManualSeasonSelection = true
        if isSelected {
            selectedSeasons.insert(seasonNumber)
        } else {
            selectedSeasons.remove(seasonNumber)
        }
    }

    func loadServiceOptionsIfNeeded() async {
        guard requiresAdvancedConfiguration else { return }
        guard let requestType = selectedRequestType else { return }
        guard loadedRequestType != requestType else { return }
        await loadServers(for: requestType)
    }

    func selectServer(id: Int) async {
        guard selectedServerId != id else { return }
        selectedServerId = id
        await loadServiceDetail(for: id)
    }

    func submitRequest() async {
        guard let payload = buildPayload() else { return }
        guard let requestRepository = requestRepository else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            if let requestId = existingRequest?.id {
                try await requestRepository.updateRequest(id: requestId, payload: payload)
            } else {
                try await requestRepository.createRequest(payload)
            }
            didComplete = true
        } catch {
            presentError(error)
        }
    }

    func cancelRequest() async {
        guard let requestRepository = requestRepository else { return }
        guard let requestId = existingRequest?.id else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await requestRepository.cancelRequest(id: requestId)
            didComplete = true
        } catch {
            presentError(error)
        }
    }

    private func loadServers(for requestType: SeerrMediaRequestType) async {
        guard let serviceRepository = serviceRepository else { return }

        isLoadingServices = true
        servicesErrorMessage = nil
        defer { isLoadingServices = false }

        do {
            if isMovie {
                let servers = try await serviceRepository.getRadarrServers()
                radarrServers = servers.filter { ($0.is4k ?? false) == requestType.is4k }
                if radarrServers.isEmpty {
                    servicesErrorMessage = String(localized: "seerr.request.services.unavailable")
                    return
                }
                selectedServerId = selectDefaultServer(from: radarrServers.map { SeerrServiceServerOption(id: $0.id, name: $0.name ?? "", isDefault: $0.isDefault ?? false) })
                if let selectedServerId {
                    await loadServiceDetail(for: selectedServerId)
                }
            } else if isTV {
                let servers = try await serviceRepository.getSonarrServers()
                sonarrServers = servers.filter { ($0.is4k ?? false) == requestType.is4k }
                if sonarrServers.isEmpty {
                    servicesErrorMessage = String(localized: "seerr.request.services.unavailable")
                    return
                }
                selectedServerId = selectDefaultServer(from: sonarrServers.map { SeerrServiceServerOption(id: $0.id, name: $0.name ?? "", isDefault: $0.isDefault ?? false) })
                if let selectedServerId {
                    await loadServiceDetail(for: selectedServerId)
                }
            }
            loadedRequestType = requestType
        } catch {
            servicesErrorMessage = errorMessage(for: error)
        }
    }

    private func loadServiceDetail(for serverId: Int) async {
        guard let serviceRepository = serviceRepository else { return }

        isLoadingServices = true
        servicesErrorMessage = nil
        defer { isLoadingServices = false }

        do {
            if isMovie {
                let detail = try await serviceRepository.getRadarrService(id: serverId)
                serviceProfiles = detail.profiles
                serviceRootFolders = detail.rootFolders
                serviceTags = detail.tags
                selectedProfileId = selectProfileId(defaultID: detail.server.activeProfileId, profiles: detail.profiles)
                selectedRootFolder = selectRootFolder(defaultPath: detail.server.activeDirectory, rootFolders: detail.rootFolders)
                selectedTags = []
            } else if isTV {
                let detail = try await serviceRepository.getSonarrService(id: serverId)
                serviceProfiles = detail.profiles
                serviceRootFolders = detail.rootFolders
                serviceTags = detail.tags
                let defaultProfileId = isAnimeRequest ? detail.server.activeAnimeProfileId : detail.server.activeProfileId
                let defaultRootFolder = isAnimeRequest ? detail.server.activeAnimeDirectory : detail.server.activeDirectory
                selectedProfileId = selectProfileId(defaultID: defaultProfileId, profiles: detail.profiles)
                selectedRootFolder = selectRootFolder(defaultPath: defaultRootFolder, rootFolders: detail.rootFolders)
                selectedTags = []
            }
        } catch {
            servicesErrorMessage = errorMessage(for: error)
        }
    }

    private func seedSelectedSeasonsIfNeeded() {
        guard isTV else { return }
        guard let requestType = selectedRequestType else { return }

        if !allowsPartialRequests {
            let requestable = SeerrMediaRequestAvailability.requestableSeasons(media: media, is4k: requestType.is4k)
            var selection = Set(requestable.compactMap(\.seasonNumber))
            selection.formUnion(existingRequestSeasonNumbers)
            selectedSeasons = selection
            return
        }

        if let existingRequest {
            if let requestSeasons = existingRequest.seasons, !requestSeasons.isEmpty {
                selectedSeasons = Set(requestSeasons.compactMap(\.seasonNumber))
            } else {
                selectedSeasons = Set(seasons.compactMap(\.seasonNumber))
            }
            return
        }

        selectedSeasons = Set(
            SeerrMediaRequestAvailability.requestableSeasons(media: media, is4k: requestType.is4k)
                .compactMap(\.seasonNumber)
        )
    }

    private var existingRequestSeasonNumbers: Set<Int> {
        guard let existingRequest else { return [] }
        if let requestSeasons = existingRequest.seasons, !requestSeasons.isEmpty {
            return Set(requestSeasons.compactMap(\.seasonNumber))
        }
        return Set(seasons.compactMap(\.seasonNumber))
    }

    private func resetServiceSelection() {
        loadedRequestType = nil
        radarrServers = []
        sonarrServers = []
        serviceProfiles = []
        serviceRootFolders = []
        serviceTags = []
        selectedServerId = nil
        selectedProfileId = nil
        selectedRootFolder = nil
        selectedTags = []
        servicesErrorMessage = nil
    }

    private func selectDefaultServer(from servers: [SeerrServiceServerOption]) -> Int? {
        if let defaultServer = servers.first(where: { $0.isDefault }) {
            return defaultServer.id
        }
        return servers.first?.id
    }

    private func selectProfileId(defaultID: Int?, profiles: [SeerrServiceProfile]) -> Int? {
        if let defaultID, profiles.contains(where: { $0.id == defaultID }) {
            return defaultID
        }
        if profiles.count == 1 {
            return profiles.first?.id
        }
        return profiles.first?.id
    }

    private func selectRootFolder(defaultPath: String?, rootFolders: [SeerrServiceRootFolder]) -> String? {
        if let defaultPath, rootFolders.contains(where: { $0.path == defaultPath }) {
            return defaultPath
        }
        if rootFolders.count == 1 {
            return rootFolders.first?.path
        }
        return rootFolders.first?.path
    }

    private func buildPayload() -> SeerrMediaRequestPayload? {
        guard let requestType = selectedRequestType else { return nil }
        guard let mediaType = media.mediaType else { return nil }

        var tvdbId: Int?
        var seasonsPayload: [Int]?
        if isTV {
            guard let externalId = media.externalIds?.tvdbId else {
                presentErrorMessage(key: "seerr.request.error.missingTvdb")
                return nil
            }
            tvdbId = externalId
            if selectedSeasons.isEmpty {
                presentErrorMessage(key: "seerr.request.error.noSeasons")
                return nil
            }
            seasonsPayload = selectedSeasons.sorted()
        }

        var serverId: Int?
        var profileId: Int?
        var rootFolder: String?
        var tags: [Int]?
        if requiresAdvancedConfiguration {
            guard let selectedServerId, let selectedProfileId, let selectedRootFolder else {
                presentErrorMessage(key: "seerr.request.error.missingOptions")
                return nil
            }
            serverId = selectedServerId
            profileId = selectedProfileId
            rootFolder = selectedRootFolder
            tags = selectedTags
        }

        return SeerrMediaRequestPayload(
            mediaId: media.id,
            mediaType: mediaType,
            is4k: requestType.is4k,
            tvdbId: tvdbId,
            seasons: seasonsPayload,
            serverId: serverId,
            profileId: profileId,
            rootFolder: rootFolder,
            tags: tags,
        )
    }

    private var requestRepository: SeerrRequestRepository? {
        guard let baseURL = baseURL else { return nil }
        return SeerrRequestRepository(baseURL: baseURL, session: session)
    }

    private var serviceRepository: SeerrServiceRepository? {
        guard let baseURL = baseURL else { return nil }
        return SeerrServiceRepository(baseURL: baseURL, session: session)
    }

    private var baseURL: URL? {
        guard let baseURLString = store.baseURLString else { return nil }
        return URL(string: baseURLString)
    }

    private var canRequestStandard: Bool {
        guard isMovie || isTV else { return false }
        let permissions: [SeerrPermission] = isTV ? [.request, .requestTV] : [.request, .requestMovie]
        return permissionService.hasPermission(permissions, user: store.user, options: .init(type: .or))
    }

    private var canRequest4K: Bool {
        guard isMovie || isTV else { return false }
        guard is4kEnabledForMedia else { return false }
        let permissions: [SeerrPermission] = isTV ? [.request4K, .request4KTV] : [.request4K, .request4KMovie]
        return permissionService.hasPermission(permissions, user: store.user, options: .init(type: .or))
    }

    private var isAnimeRequest: Bool {
        guard isTV else { return false }
        return media.keywords?.contains(where: { $0.name?.lowercased() == "anime" }) ?? false
    }

    private var is4kEnabledForMedia: Bool {
        guard let settings = store.settings else { return false }
        if isMovie {
            return settings.movie4kEnabled
        }
        if isTV {
            return settings.series4kEnabled
        }
        return false
    }

    private var allowsPartialRequests: Bool {
        store.settings?.partialRequestsEnabled ?? true
    }

    var partialRequestsDisabledMessageKey: String? {
        allowsPartialRequests ? nil : "seerr.request.seasons.partialDisabled"
    }

    var requiresAdvancedConfiguration: Bool {
        permissionService.hasPermission([
            .manageRequests,
            .requestAdvanced,
        ], user: store.user, options: .init(type: .or))
    }

    private func errorMessage(for error: Error) -> String {
        let key = switch error {
        case SeerrAPIError.invalidURL:
            "integrations.seerr.error.invalidURL"
        case SeerrAPIError.requestFailed:
            "integrations.seerr.error.connection"
        default:
            "common.errors.tryAgainLater"
        }
        return String(localized: .init(key))
    }

    private func presentError(_ error: Error) {
        errorMessage = errorMessage(for: error)
        isShowingError = true
    }

    private func presentErrorMessage(key: String) {
        errorMessage = String(localized: .init(key))
        isShowingError = true
    }
}

struct SeerrServiceServerOption: Identifiable, Hashable {
    let id: Int
    let name: String
    let isDefault: Bool
}
