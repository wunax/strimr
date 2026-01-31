import Foundation

struct SeerrMediaRequestAvailability {
    static func seasonAvailabilityBadge(
        media: SeerrMedia,
        seasonNumber: Int,
        is4k: Bool,
    ) -> SeerrSeasonAvailabilityBadge? {
        if let seasonStatus = seasonStatus(for: media, seasonNumber: seasonNumber, is4k: is4k),
           seasonStatus != .unknown {
            return .media(seasonStatus)
        }

        let matchingStatuses = activeRequests(for: media, is4k: is4k).compactMap { request -> SeerrMediaRequestStatus? in
            let requestStatus = request.status
            if let requestSeasons = request.seasons, !requestSeasons.isEmpty {
                guard let seasonInfo = requestSeasons.first(where: { $0.seasonNumber == seasonNumber }) else {
                    return nil
                }
                if let seasonStatus = seasonInfo.status, seasonStatus != .declined, seasonStatus != .completed {
                    return seasonStatus
                }
                return requestStatus
            }
            return requestStatus
        }

        let requestBadgePriority: [SeerrMediaRequestStatus] = [.pending, .approved]
        if let status = requestBadgePriority.first(where: { matchingStatuses.contains($0) }) {
            return .request(status)
        }
        return nil
    }

    static func isSeasonRequestable(
        media: SeerrMedia,
        seasonNumber: Int,
        is4k: Bool,
    ) -> Bool {
        if let seasonStatus = seasonStatus(for: media, seasonNumber: seasonNumber, is4k: is4k),
           seasonStatus != .unknown {
            return false
        }

        return !hasActiveRequest(for: media, seasonNumber: seasonNumber, is4k: is4k)
    }

    static func requestableSeasons(
        media: SeerrMedia,
        is4k: Bool,
    ) -> [SeerrSeason] {
        let seasons = media.seasons?.filter { $0.seasonNumber != nil } ?? []
        return seasons.filter { season in
            guard let seasonNumber = season.seasonNumber else { return false }
            return isSeasonRequestable(media: media, seasonNumber: seasonNumber, is4k: is4k)
        }
    }

    static func hasRequestableSeasons(
        media: SeerrMedia,
        is4k: Bool,
    ) -> Bool {
        !requestableSeasons(media: media, is4k: is4k).isEmpty
    }

    static func pendingRequest(
        in media: SeerrMedia,
        for user: SeerrUser?,
    ) -> SeerrRequest? {
        guard let user else { return nil }
        return media.mediaInfo?.requests?.first(where: { request in
            request.status == .pending && request.requestedBy?.id == user.id
        })
    }

    private static func seasonStatus(
        for media: SeerrMedia,
        seasonNumber: Int,
        is4k: Bool,
    ) -> SeerrMediaStatus? {
        let seasonInfo = media.mediaInfo?.seasons?.first(where: { $0.seasonNumber == seasonNumber })
        return is4k ? seasonInfo?.status4k : seasonInfo?.status
    }

    private static func hasActiveRequest(
        for media: SeerrMedia,
        seasonNumber: Int,
        is4k: Bool,
    ) -> Bool {
        activeRequests(for: media, is4k: is4k).contains { request in
            if let requestSeasons = request.seasons, !requestSeasons.isEmpty {
                guard let seasonInfo = requestSeasons.first(where: { $0.seasonNumber == seasonNumber }) else {
                    return false
                }
                if let seasonStatus = seasonInfo.status {
                    return seasonStatus != .declined && seasonStatus != .completed
                }
                return true
            }
            return true
        }
    }

    private static func activeRequests(for media: SeerrMedia, is4k: Bool) -> [SeerrRequest] {
        media.mediaInfo?.requests?.filter { request in
            guard request.is4k ?? false == is4k else { return false }
            guard let status = request.status else { return false }
            return status != .declined && status != .completed
        } ?? []
    }
}
