import Foundation
@testable import Strimr
import Testing

struct PlexServerModelsTests {
    @Test func `server root exposes the media deletion setting`() throws {
        let root = try Fixtures.decode(PlexServerRootResponse.self, from: "plex-server-root")

        #expect(root.mediaContainer.allowMediaDeletion == true)
    }

    @Test func `owner without a Plex Home administers the server`() {
        #expect(PlexServerRights.isAdministrator(
            resourceOwned: true,
            homeUsers: [],
            userUUID: "owner",
            accountID: "owner",
        ))
    }

    @Test func `server shared with the account is not administered`() {
        #expect(!PlexServerRights.isAdministrator(
            resourceOwned: false,
            homeUsers: [],
            userUUID: "owner",
            accountID: "owner",
        ))
        #expect(!PlexServerRights.isAdministrator(
            resourceOwned: nil,
            homeUsers: [],
            userUUID: "owner",
            accountID: "owner",
        ))
    }

    @Test func `only the Home admin administers an owned server`() {
        let users = [homeUser("owner", admin: true), homeUser("kid", admin: false), homeUser("guest", admin: nil)]

        #expect(PlexServerRights.isAdministrator(
            resourceOwned: true,
            homeUsers: users,
            userUUID: "owner",
            accountID: "owner",
        ))
        #expect(!PlexServerRights.isAdministrator(
            resourceOwned: true,
            homeUsers: users,
            userUUID: "kid",
            accountID: "owner",
        ))
        #expect(!PlexServerRights.isAdministrator(
            resourceOwned: true,
            homeUsers: users,
            userUUID: "guest",
            accountID: "owner",
        ))
    }

    @Test func `account owner missing from a loaded Home still administers`() {
        #expect(PlexServerRights.isAdministrator(
            resourceOwned: true,
            homeUsers: [homeUser("kid", admin: false)],
            userUUID: "owner",
            accountID: "owner",
        ))
    }

    private func homeUser(_ uuid: String, admin: Bool?) -> PlexHomeUser {
        PlexHomeUser(
            id: nil,
            uuid: uuid,
            title: nil,
            username: nil,
            email: nil,
            friendlyName: nil,
            thumb: nil,
            protected: nil,
            pin: nil,
            admin: admin,
        )
    }
}
