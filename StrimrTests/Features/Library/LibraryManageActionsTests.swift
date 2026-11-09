import Foundation
@testable import Strimr
import Testing

@MainActor
struct LibraryManageActionsTests {
    private struct Failure: LocalizedError {
        var errorDescription: String? {
            "Server said no"
        }
    }

    private final class Calls {
        var performed: [(LibraryManageAction, String)] = []
        var updatesStarted: [String] = []
    }

    private func makeActions(
        calls: Calls = Calls(),
        error: Error? = nil,
        supportsAnalyze: Bool = true,
        supportsTrash: Bool = true,
    ) -> LibraryManageActions {
        LibraryManageActions(management: LibraryManageActions.Management(
            supportsAnalyze: supportsAnalyze,
            supportsTrash: supportsTrash,
            perform: { action, id in
                calls.performed.append((action, id))
                if let error {
                    throw error
                }
            },
            updateStarted: { calls.updatesStarted.append($0) },
        ))
    }

    private func plexLibrary(
        type: MediaKind = .movie,
        sectionId: Int? = 3,
        isShared: Bool = false,
    ) -> Library {
        Library(
            id: sectionId.map(String.init) ?? "shared",
            title: "Movies",
            type: type,
            sectionId: sectionId,
            isShared: isShared,
            server: ServerIdentity(provider: .plex, id: "server"),
        )
    }

    private func jellyfinLibrary(type: MediaKind = .series) -> Library {
        Library(id: "library", title: "Shows", type: type, server: ServerIdentity(provider: .jellyfin, id: "server"))
    }

    @Test func `plex offers every action, jellyfin only scanning and refreshing`() {
        #expect(makeActions().actions(for: plexLibrary())
            == [.scan, .refreshMetadata, .analyze, .emptyTrash])
        #expect(makeActions(supportsAnalyze: false, supportsTrash: false).actions(for: jellyfinLibrary())
            == [.scan, .refreshMetadata])
    }

    @Test func `nothing is offered without the right to manage the library`() {
        let actions = LibraryManageActions(management: nil)

        #expect(actions.actions(for: plexLibrary()).isEmpty)
        #expect(actions.actions(for: jellyfinLibrary()).isEmpty)
    }

    @Test func `shared items, collections and playlists are not managed`() {
        let actions = makeActions()

        #expect(actions.actions(for: plexLibrary(sectionId: nil, isShared: true)).isEmpty)
        #expect(actions.actions(for: jellyfinLibrary(type: .collection)).isEmpty)
        #expect(actions.actions(for: jellyfinLibrary(type: .playlist)).isEmpty)
    }

    @Test func `actions target the plex section and the jellyfin library`() async {
        let calls = Calls()
        let actions = makeActions(calls: calls)

        #expect(await actions.perform(.scan, on: plexLibrary(sectionId: 7)) == .succeeded)
        #expect(await actions.perform(.refreshMetadata, on: jellyfinLibrary()) == .succeeded)

        #expect(calls.performed.map(\.0) == [.scan, .refreshMetadata])
        #expect(calls.performed.map(\.1) == ["7", "library"])
        #expect(calls.updatesStarted == ["7", "library"])
    }

    @Test func `unsupported actions are skipped`() async {
        let calls = Calls()
        let actions = makeActions(calls: calls, supportsAnalyze: false, supportsTrash: false)

        #expect(await actions.perform(.analyze, on: plexLibrary()) == .cancelled)
        #expect(await actions.perform(.emptyTrash, on: plexLibrary()) == .cancelled)
        #expect(calls.performed.isEmpty)
    }

    @Test func `server refusal explains the lost right and announces no update`() async {
        let calls = Calls()
        let outcome = await makeActions(calls: calls, error: PlexAPIError.requestFailed(statusCode: 403))
            .perform(.emptyTrash, on: plexLibrary())

        #expect(outcome == .failed(message: String(localized: "media.manage.error.forbidden")))
        #expect(calls.updatesStarted.isEmpty)
    }

    @Test func `failures carry the server message`() async {
        let outcome = await makeActions(error: Failure()).perform(.scan, on: jellyfinLibrary())

        #expect(outcome == .failed(message: "Server said no"))
    }
}
