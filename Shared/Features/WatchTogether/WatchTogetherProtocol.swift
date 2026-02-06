import Foundation

enum WatchTogetherProtocol {
    static let version = 1
}

enum WatchTogetherClientMessage: Codable {
    case createSession(CreateSessionRequest)
    case joinSession(JoinSessionRequest)
    case leaveSession(LeaveSessionRequest)
    case setReady(SetReadyRequest)
    case setSelectedMedia(SetSelectedMediaRequest)
    case mediaAccess(MediaAccessRequest)
    case startPlayback(StartPlaybackRequest)
    case stopPlayback(StopPlaybackRequest)
    case playerEvent(PlayerEventRequest)
    case ping(PingRequest)

    private enum CodingKeys: String, CodingKey {
        case v
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case createSession
        case joinSession
        case leaveSession
        case setReady
        case setSelectedMedia
        case mediaAccess
        case startPlayback
        case stopPlayback
        case playerEvent
        case ping
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decode(Int.self, forKey: .v)
        let type = try container.decode(MessageType.self, forKey: .type)

        switch type {
        case .createSession:
            let payload = try container.decode(CreateSessionRequest.self, forKey: .payload)
            self = .createSession(payload)
        case .joinSession:
            let payload = try container.decode(JoinSessionRequest.self, forKey: .payload)
            self = .joinSession(payload)
        case .leaveSession:
            let payload = try container.decode(LeaveSessionRequest.self, forKey: .payload)
            self = .leaveSession(payload)
        case .setReady:
            let payload = try container.decode(SetReadyRequest.self, forKey: .payload)
            self = .setReady(payload)
        case .setSelectedMedia:
            let payload = try container.decode(SetSelectedMediaRequest.self, forKey: .payload)
            self = .setSelectedMedia(payload)
        case .mediaAccess:
            let payload = try container.decode(MediaAccessRequest.self, forKey: .payload)
            self = .mediaAccess(payload)
        case .startPlayback:
            let payload = try container.decode(StartPlaybackRequest.self, forKey: .payload)
            self = .startPlayback(payload)
        case .stopPlayback:
            let payload = try container.decode(StopPlaybackRequest.self, forKey: .payload)
            self = .stopPlayback(payload)
        case .playerEvent:
            let payload = try container.decode(PlayerEventRequest.self, forKey: .payload)
            self = .playerEvent(payload)
        case .ping:
            let payload = try container.decode(PingRequest.self, forKey: .payload)
            self = .ping(payload)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(WatchTogetherProtocol.version, forKey: .v)

        switch self {
        case let .createSession(payload):
            try container.encode(MessageType.createSession, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .joinSession(payload):
            try container.encode(MessageType.joinSession, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .leaveSession(payload):
            try container.encode(MessageType.leaveSession, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .setReady(payload):
            try container.encode(MessageType.setReady, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .setSelectedMedia(payload):
            try container.encode(MessageType.setSelectedMedia, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .mediaAccess(payload):
            try container.encode(MessageType.mediaAccess, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .startPlayback(payload):
            try container.encode(MessageType.startPlayback, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .stopPlayback(payload):
            try container.encode(MessageType.stopPlayback, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .playerEvent(payload):
            try container.encode(MessageType.playerEvent, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .ping(payload):
            try container.encode(MessageType.ping, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

struct CreateSessionRequest: Codable, Hashable {
    let plexServerId: String
    let participantId: String
    let displayName: String
}

struct JoinSessionRequest: Codable, Hashable {
    let code: String
    let plexServerId: String
    let participantId: String
    let displayName: String
}

struct LeaveSessionRequest: Codable, Hashable {
    let endForAll: Bool?
}

struct SetReadyRequest: Codable, Hashable {
    let isReady: Bool
}

struct SetSelectedMediaRequest: Codable, Hashable {
    let media: WatchTogetherSelectedMedia
}

struct MediaAccessRequest: Codable, Hashable {
    let hasAccess: Bool
}

struct StartPlaybackRequest: Codable, Hashable {
    let ratingKey: String
    let type: PlexItemType
}

struct StopPlaybackRequest: Codable, Hashable {
    let reason: String?
}

struct PlayerEventRequest: Codable, Hashable {
    let event: WatchTogetherPlayerEvent
}

struct PingRequest: Codable, Hashable {
    let sentAtMs: Int64
}

enum WatchTogetherServerMessage: Codable {
    case created(CreatedResponse)
    case joined(JoinedResponse)
    case lobbySnapshot(WatchTogetherLobbySnapshot)
    case participantUpdate(ParticipantUpdate)
    case sessionEnded(SessionEnded)
    case error(WatchTogetherServerError)
    case pong(PongResponse)
    case startPlayback(WatchTogetherStartPlayback)
    case playbackStopped(PlaybackStopped)
    case playerEvent(WatchTogetherPlayerEvent)

    private enum CodingKeys: String, CodingKey {
        case v
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case created
        case joined
        case lobbySnapshot
        case participantUpdate
        case sessionEnded
        case error
        case pong
        case startPlayback
        case playbackStopped
        case playerEvent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decode(Int.self, forKey: .v)
        let type = try container.decode(MessageType.self, forKey: .type)

        switch type {
        case .created:
            let payload = try container.decode(CreatedResponse.self, forKey: .payload)
            self = .created(payload)
        case .joined:
            let payload = try container.decode(JoinedResponse.self, forKey: .payload)
            self = .joined(payload)
        case .lobbySnapshot:
            let payload = try container.decode(WatchTogetherLobbySnapshot.self, forKey: .payload)
            self = .lobbySnapshot(payload)
        case .participantUpdate:
            let payload = try container.decode(ParticipantUpdate.self, forKey: .payload)
            self = .participantUpdate(payload)
        case .sessionEnded:
            let payload = try container.decode(SessionEnded.self, forKey: .payload)
            self = .sessionEnded(payload)
        case .error:
            let payload = try container.decode(WatchTogetherServerError.self, forKey: .payload)
            self = .error(payload)
        case .pong:
            let payload = try container.decode(PongResponse.self, forKey: .payload)
            self = .pong(payload)
        case .startPlayback:
            let payload = try container.decode(WatchTogetherStartPlayback.self, forKey: .payload)
            self = .startPlayback(payload)
        case .playbackStopped:
            let payload = try container.decode(PlaybackStopped.self, forKey: .payload)
            self = .playbackStopped(payload)
        case .playerEvent:
            let payload = try container.decode(WatchTogetherPlayerEvent.self, forKey: .payload)
            self = .playerEvent(payload)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(WatchTogetherProtocol.version, forKey: .v)

        switch self {
        case let .created(payload):
            try container.encode(MessageType.created, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .joined(payload):
            try container.encode(MessageType.joined, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .lobbySnapshot(payload):
            try container.encode(MessageType.lobbySnapshot, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .participantUpdate(payload):
            try container.encode(MessageType.participantUpdate, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .sessionEnded(payload):
            try container.encode(MessageType.sessionEnded, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .error(payload):
            try container.encode(MessageType.error, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .pong(payload):
            try container.encode(MessageType.pong, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .startPlayback(payload):
            try container.encode(MessageType.startPlayback, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .playbackStopped(payload):
            try container.encode(MessageType.playbackStopped, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .playerEvent(payload):
            try container.encode(MessageType.playerEvent, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

struct CreatedResponse: Codable, Hashable {
    let code: String
    let hostId: String
    let participantId: String
}

struct JoinedResponse: Codable, Hashable {
    let code: String
    let hostId: String
    let participantId: String
}

struct ParticipantUpdate: Codable, Hashable {
    let participant: WatchTogetherParticipant
}

struct SessionEnded: Codable, Hashable {
    let reason: String?
}

struct PlaybackStopped: Codable, Hashable {
    let reason: String?
}

struct PongResponse: Codable, Hashable {
    let sentAtMs: Int64
    let receivedAtMs: Int64
}
