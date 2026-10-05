import Foundation
import Observation

/// Entry of a Plex server's custom address, shared by server selection and the server's settings.
@MainActor
@Observable
final class CustomServerAddressModel: Identifiable {
    let id = UUID()
    var address: String
    var error: String?
    private(set) var isWorking = false

    var canRemove: Bool {
        remove != nil
    }

    @ObservationIgnored private let save: (URL) async throws -> Void
    @ObservationIgnored private let remove: (() async throws -> Void)?
    @ObservationIgnored private let onDone: () -> Void

    /// - Parameters:
    ///   - remove: offered only when the server already has a custom address.
    ///   - onDone: called once the address is saved or removed, or the entry cancelled.
    init(
        address: URL?,
        save: @escaping (URL) async throws -> Void,
        remove: (() async throws -> Void)?,
        onDone: @escaping () -> Void,
    ) {
        self.address = address?.absoluteString ?? ""
        self.save = save
        self.remove = remove
        self.onDone = onDone
    }

    func connect() async {
        guard !isWorking else { return }

        let url: URL
        do {
            url = try PlexAPIContext.normalizedCustomServerURL(address)
            address = url.absoluteString
        } catch {
            self.error = String(localized: "serverSelection.customAddress.error.invalid")
            return
        }

        isWorking = true
        error = nil
        defer { isWorking = false }

        do {
            try await save(url)
            onDone()
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            self.error = String(localized: "serverSelection.customAddress.error.connection")
        }
    }

    func removeAddress() async {
        guard !isWorking, let remove else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }

        do {
            try await remove()
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
        onDone()
    }

    func cancel() {
        guard !isWorking else { return }
        onDone()
    }
}
