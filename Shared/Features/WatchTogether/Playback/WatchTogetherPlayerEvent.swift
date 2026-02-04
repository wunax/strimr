import Foundation

struct WatchTogetherPlayerEvent: Codable, Hashable, Identifiable {
    enum EventType: String, Codable {
        case play
        case pause
        case seek
        case setRate
    }

    let eventId: UUID
    let senderId: String
    let type: EventType
    let positionSeconds: Double?
    let rate: Float?
    let clientSentAtMs: Int64
    let serverReceivedAtMs: Int64?

    var id: UUID { eventId }

    private enum CodingKeys: String, CodingKey {
        case eventId
        case senderId
        case type
        case positionSeconds
        case rate
        case clientSentAtMs
        case serverReceivedAtMs
    }

    init(
        senderId: String,
        type: EventType,
        positionSeconds: Double? = nil,
        rate: Float? = nil,
        clientSentAtMs: Int64,
        serverReceivedAtMs: Int64? = nil,
        eventId: UUID = UUID(),
    ) {
        self.eventId = eventId
        self.senderId = senderId
        self.type = type
        self.positionSeconds = positionSeconds
        self.rate = rate
        self.clientSentAtMs = clientSentAtMs
        self.serverReceivedAtMs = serverReceivedAtMs
    }
}
