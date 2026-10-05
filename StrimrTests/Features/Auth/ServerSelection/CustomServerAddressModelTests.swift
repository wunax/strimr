import Foundation
@testable import Strimr
import Testing

@MainActor
struct CustomServerAddressModelTests {
    private struct ConnectionFailure: Error {}

    @Test func `an invalid address is rejected before contacting the server`() async {
        var saved: [URL] = []
        var isDone = false
        let model = CustomServerAddressModel(
            address: nil,
            save: { saved.append($0) },
            remove: nil,
            onDone: { isDone = true },
        )
        model.address = "plex.example.com"

        await model.connect()

        #expect(saved.isEmpty)
        #expect(model.error != nil)
        #expect(!isDone)
    }

    @Test func `a reachable address is saved normalized`() async throws {
        var saved: [URL] = []
        var isDone = false
        let model = CustomServerAddressModel(
            address: nil,
            save: { saved.append($0) },
            remove: nil,
            onDone: { isDone = true },
        )
        model.address = " https://plex.example.com:32400/ "

        await model.connect()

        #expect(try saved == [#require(URL(string: "https://plex.example.com:32400"))])
        #expect(model.error == nil)
        #expect(isDone)
    }

    @Test func `an unreachable address keeps the entry open`() async {
        var isDone = false
        let model = CustomServerAddressModel(
            address: nil,
            save: { _ in throw ConnectionFailure() },
            remove: nil,
            onDone: { isDone = true },
        )
        model.address = "https://plex.example.com"

        await model.connect()

        #expect(model.error != nil)
        #expect(!model.isWorking)
        #expect(!isDone)
    }

    @Test func `removal is offered only for an existing address`() async {
        var removed = false
        var isDone = false
        let existing = CustomServerAddressModel(
            address: URL(string: "https://plex.example.com"),
            save: { _ in },
            remove: { removed = true },
            onDone: { isDone = true },
        )
        let fresh = CustomServerAddressModel(address: nil, save: { _ in }, remove: nil, onDone: {})

        #expect(existing.address == "https://plex.example.com")
        #expect(existing.canRemove)
        #expect(!fresh.canRemove)

        await existing.removeAddress()

        #expect(removed)
        #expect(isDone)
    }
}
