import Foundation
import Observation

/// Sign-out with downloads: the progress journal is pushed first when possible, then the user chooses whether the
/// downloads of the signed-out owner are kept (visible again when they sign back in) or deleted. The browsing cache of
/// the owner is always deleted.
@MainActor
@Observable
final class SignOutFlow {
    struct DownloadsPrompt: Equatable {
        let count: Int
        let bytes: Int64
        let hasUnsyncedProgress: Bool
    }

    private(set) var isSigningOut = false
    var downloadsPrompt: DownloadsPrompt?
    @ObservationIgnored private var owner: MediaOwner?

    /// Starts signing out; returns once the session is closed or when the downloads prompt must be answered.
    func begin(sessionManager: SessionManager, downloadManager: DownloadManager) async {
        guard !isSigningOut else { return }
        guard let owner = sessionManager.mediaServices?.owner else {
            await sessionManager.signOut()
            return
        }
        isSigningOut = true
        self.owner = owner
        let synchronized = await OfflineCoordinator.shared.synchronizeProgressNow(owner: owner)
        let downloads = downloadManager.items.filter { $0.ownerID == owner.id }
        guard !downloads.isEmpty else {
            await finish(deleteDownloads: false, sessionManager: sessionManager, downloadManager: downloadManager)
            return
        }
        downloadsPrompt = DownloadsPrompt(
            count: downloads.count,
            bytes: downloads.reduce(0) { $0 + ($1.metadata.fileSize ?? $1.totalBytes) },
            hasUnsyncedProgress: !synchronized,
        )
    }

    func finish(deleteDownloads: Bool, sessionManager: SessionManager, downloadManager: DownloadManager) async {
        downloadsPrompt = nil
        if let owner {
            if deleteDownloads {
                await downloadManager.deleteDownloads(ownerID: owner.id)
                OfflineCoordinator.shared.store?.deletePinnedData(owner: owner)
            }
            OfflineCoordinator.shared.store?.clearCache(owner: owner)
        }
        owner = nil
        await sessionManager.signOut()
        isSigningOut = false
    }

    func cancel() {
        downloadsPrompt = nil
        owner = nil
        isSigningOut = false
    }
}
