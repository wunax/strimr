@testable import Strimr
import Testing

struct DeepLinkProfileGateTests {
    private let anna = StrimrProfile.local(LocalProfile(id: "local.anna", name: "Anna"))
    private let kids = StrimrProfile.local(LocalProfile(
        id: "local.kids",
        name: "Enfants",
        pin: LocalProfilePIN(pin: "1234"),
    ))

    private func decide(
        _ reference: String,
        active: String? = "local.anna",
        status: SessionManager.Status = .ready,
        awaited: String? = nil,
    ) -> DeepLinkProfileGate.Decision {
        DeepLinkProfileGate.decide(
            reference: reference,
            profiles: [anna, kids],
            activeProfileID: active,
            status: status,
            awaitedProfileID: awaited,
        )
    }

    @Test func `profiles match by id, then by name ignoring case and accents`() {
        #expect(DeepLinkProfileGate.profile(named: "local.kids", in: [anna, kids]) == kids)
        #expect(DeepLinkProfileGate.profile(named: "enfants", in: [anna, kids]) == kids)
        #expect(DeepLinkProfileGate.profile(named: "ANNA", in: [anna, kids]) == anna)
        #expect(DeepLinkProfileGate.profile(named: "Bob", in: [anna, kids]) == nil)
    }

    @Test func `the active profile lets the link through`() {
        #expect(decide("Anna") == .proceed)
    }

    @Test func `another profile is activated, or asks its PIN`() {
        #expect(decide("Anna", active: "local.kids") == .activate("local.anna"))
        #expect(decide("Enfants") == .askForPIN("local.kids"))
        #expect(decide("Anna", active: nil, status: .needsProfileSelection) == .activate("local.anna"))
    }

    @Test func `an unknown profile is reported`() {
        #expect(decide("Bob") == .profileNotFound)
    }

    @Test func `the session settles first`() {
        #expect(decide("Anna", status: .hydrating) == .wait)
        #expect(decide("Anna", status: .migrationFailed) == .wait)
        #expect(decide("Anna", status: .needsAccount) == .drop)
    }

    @Test func `while the PIN is typed the link waits, and is dropped for another profile`() {
        #expect(decide("Enfants", status: .needsProfileSelection, awaited: "local.kids") == .wait)
        #expect(decide("Enfants", active: "local.kids", awaited: "local.kids") == .proceed)
        #expect(decide("Enfants", active: "local.anna", awaited: "local.kids") == .drop)
    }
}
