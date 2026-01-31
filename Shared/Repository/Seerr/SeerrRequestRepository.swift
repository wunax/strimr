import Foundation

final class SeerrRequestRepository {
    private let client: SeerrNetworkClient

    init(baseURL: URL, session: URLSession = .shared) {
        client = SeerrNetworkClient(baseURL: baseURL, session: session)
    }

    func createRequest(_ payload: SeerrMediaRequestPayload) async throws {
        try await client.send(path: "request", method: "POST", body: payload)
    }

    func updateRequest(id: Int, payload: SeerrMediaRequestPayload) async throws {
        try await client.send(path: "request/\(id)", method: "PUT", body: payload)
    }

    func cancelRequest(id: Int) async throws {
        try await client.send(path: "request/\(id)", method: "DELETE")
    }

    func updateRequestStatus(id: Int, status: SeerrMediaRequestStatus) async throws {
        let action = switch status {
        case .approved:
            "approve"
        case .declined:
            "decline"
        case .pending, .failed, .completed:
            "approve"
        }
        try await client.send(path: "request/\(id)/\(action)", method: "POST")
    }
}
