import Foundation
import Observation

/// Removing an account that has downloads: the progress journal is pushed first when possible, then the user chooses
/// whether the downloads of its servers are deleted too. They are kept by default and stay playable offline. The
/// browsing cache of the account is always deleted.
@MainActor
@Observable
final class AccountRemovalFlow {
    struct DownloadsPrompt: Equatable {
        let count: Int
        let bytes: Int64
        let hasUnsyncedProgress: Bool
    }

    private(set) var isRemoving = false
    var downloadsPrompt: DownloadsPrompt?
    @ObservationIgnored private var accountID: String?
    @ObservationIgnored private var owners: [MediaOwner] = []

    /// Returns once the account is removed or when the downloads prompt must be answered.
    func begin(accountID: String, sessionManager: SessionManager, downloadManager: DownloadManager) async {
        guard !isRemoving else { return }
        isRemoving = true
        self.accountID = accountID
        owners = sessionManager.owners(ofAccount: accountID)
        var synchronized = true
        for owner in owners {
            let ownerSynchronized = await OfflineCoordinator.shared.synchronizeProgressNow(owner: owner)
            synchronized = synchronized && ownerSynchronized
        }
        let ownerIDs = Set(owners.map(\.id))
        let downloads = downloadManager.items.filter { $0.ownerID.map(ownerIDs.contains) ?? false }
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
        for owner in owners {
            if deleteDownloads {
                await downloadManager.deleteDownloads(ownerID: owner.id)
                OfflineCoordinator.shared.store?.deletePinnedData(owner: owner)
            }
            OfflineCoordinator.shared.store?.clearCache(owner: owner)
        }
        if let accountID {
            sessionManager.removeAccount(accountID)
        }
        accountID = nil
        owners = []
        isRemoving = false
    }

    func cancel() {
        downloadsPrompt = nil
        accountID = nil
        owners = []
        isRemoving = false
    }
}
