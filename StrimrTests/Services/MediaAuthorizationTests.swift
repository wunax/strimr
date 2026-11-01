@testable import Strimr
import Testing

struct MediaAuthorizationTests {
    @Test func `Plex administrator manages the library and deletes when the server allows it`() {
        let allowed = MediaAuthorization.plex(isAdministrator: true, allowsMediaDeletion: true)
        let refused = MediaAuthorization.plex(isAdministrator: true, allowsMediaDeletion: false)

        #expect(allowed.canManageLibrary)
        #expect(allowed.canDeleteMedia)
        #expect(refused.canManageLibrary)
        #expect(!refused.canDeleteMedia)
    }

    @Test func `Plex user who does not administer the server gets no management rights`() {
        let authorization = MediaAuthorization.plex(isAdministrator: false, allowsMediaDeletion: true)

        #expect(!authorization.canManageLibrary)
        #expect(!authorization.canDeleteMedia)
        #expect(authorization.canManageSubtitles)
    }

    @Test func `Jellyfin administrator manages and deletes`() {
        let authorization = MediaAuthorization.jellyfin(policy(isAdministrator: true, enableContentDeletion: false))

        #expect(authorization.canManageLibrary)
        #expect(authorization.canDeleteMedia)
    }

    @Test func `Jellyfin content deletion alone allows deleting but not managing`() {
        let authorization = MediaAuthorization.jellyfin(policy(isAdministrator: false, enableContentDeletion: true))

        #expect(!authorization.canManageLibrary)
        #expect(authorization.canDeleteMedia)
    }

    @Test func `Jellyfin regular user gets no management rights`() {
        let authorization = MediaAuthorization.jellyfin(policy(isAdministrator: nil, enableContentDeletion: nil))

        #expect(!authorization.canManageLibrary)
        #expect(!authorization.canDeleteMedia)
    }

    private func policy(isAdministrator: Bool?, enableContentDeletion: Bool?) -> JellyfinUserPolicy {
        JellyfinUserPolicy(
            isAdministrator: isAdministrator,
            enableMediaPlayback: true,
            enableContentDownloading: true,
            enableSubtitleManagement: nil,
            enableLiveTVAccess: nil,
            enableLiveTVManagement: nil,
            enableContentDeletion: enableContentDeletion,
        )
    }
}
