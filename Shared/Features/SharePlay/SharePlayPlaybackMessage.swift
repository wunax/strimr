import Foundation

struct SharePlayPlaybackMessage: Codable {
    enum EventType: String, Codable {
        case play
        case pause
        case seek
        case setRate
    }

    let eventId: UUID
    let type: EventType
    let positionSeconds: Double?
    let rate: Float?
    let sentAtMs: Int64

    init(
        type: EventType,
        positionSeconds: Double? = nil,
        rate: Float? = nil,
        eventId: UUID = UUID()
    ) {
        self.eventId = eventId
        self.type = type
        self.positionSeconds = positionSeconds
        self.rate = rate
        sentAtMs = Int64(Date().timeIntervalSince1970 * 1000)
    }
}
