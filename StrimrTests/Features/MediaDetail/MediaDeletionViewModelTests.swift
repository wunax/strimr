import Foundation
@testable import Strimr
import Testing

@MainActor
struct MediaDeletionViewModelTests {
    private final class Calls {
        var deleted: [String] = []
    }

    private func makeViewModel(
        calls: Calls = Calls(),
        impactError: Error? = nil,
        deletionError: Error? = nil,
    ) -> MediaDeletionViewModel {
        let quickActions = MediaQuickActions(
            supportsFavorites: true,
            setPlayed: { _, _ in },
            setFavorite: { _, _ in },
            management: MediaQuickActions.Management(
                canManageLibrary: false,
                canDelete: true,
                supportsAnalyze: false,
                refreshMetadata: { _ in },
                analyze: { _ in },
                deletionImpact: { _ in
                    if let impactError {
                        throw impactError
                    }
                    return .files(count: 1, totalSize: 4_200_000_000)
                },
                delete: { item in
                    if let deletionError {
                        throw deletionError
                    }
                    calls.deleted.append(item.id)
                },
            ),
        )
        let item = MediaItem.make(id: "item", server: ServerIdentity(provider: .plex, id: "server"))
        return MediaDeletionViewModel(item: item, quickActions: quickActions)
    }

    @Test func `deletion is offered once the impact is known, then deletes the item`() async {
        let calls = Calls()
        let viewModel = makeViewModel(calls: calls)
        #expect(!viewModel.canDelete)

        await viewModel.load()
        #expect(viewModel.state == .ready(.files(count: 1, totalSize: 4_200_000_000)))
        #expect(viewModel.canDelete)

        await viewModel.delete()
        #expect(viewModel.state == .deleted)
        #expect(calls.deleted == ["item"])
    }

    @Test func `an item the server refuses to delete cannot be confirmed`() async {
        let viewModel = makeViewModel(impactError: JellyfinAPIError.permissionDenied)

        await viewModel.load()

        #expect(viewModel.state == .failed(message: String(localized: "media.manage.delete.error.forbidden")))
        #expect(!viewModel.canDelete)
    }

    @Test func `a failed deletion shows the server refusal`() async {
        let viewModel = makeViewModel(deletionError: PlexAPIError.requestFailed(statusCode: 403))

        await viewModel.load()
        await viewModel.delete()

        #expect(viewModel.state == .failed(message: String(localized: "media.manage.delete.error.plexDisabled")))
    }
}
