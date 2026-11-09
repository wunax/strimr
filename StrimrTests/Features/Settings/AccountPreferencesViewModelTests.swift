import Foundation
@testable import Strimr
import Testing

@MainActor
struct AccountPreferencesViewModelTests {
    private struct Failure: Error {}

    private final class Service: AccountPreferencesService {
        let subtitleModes: [AccountSubtitleMode] = [.manual, .always]
        var loadError: Error?
        var applyError: Error?
        var stored = AccountPreferences(
            audioLanguage: "fr",
            selectsAudioByLanguage: true,
            subtitleLanguage: nil,
            subtitleMode: .manual,
        )
        var serverAdjustment: ((inout AccountPreferences) -> Void)?
        var appliedChanges: [AccountPreferenceChange] = []
        var beforeApplying: (() async -> Void)?

        func load() async throws -> AccountPreferences {
            if let loadError {
                throw loadError
            }
            return stored
        }

        func apply(_ change: AccountPreferenceChange) async throws -> AccountPreferences {
            appliedChanges.append(change)
            await beforeApplying?()
            if let applyError {
                throw applyError
            }
            stored = stored.applying(change)
            serverAdjustment?(&stored)
            return stored
        }
    }

    @Test func `a failed load can be retried`() async {
        let service = Service()
        service.loadError = Failure()
        let viewModel = AccountPreferencesViewModel(service: service)

        await viewModel.load()
        #expect(viewModel.loadFailed)
        #expect(viewModel.preferences == nil)

        service.loadError = nil
        await viewModel.load()
        #expect(!viewModel.loadFailed)
        #expect(viewModel.preferences == service.stored)
    }

    @Test func `a change adopts what the server stored`() async {
        let service = Service()
        service.serverAdjustment = { $0.subtitleMode = .manual }
        service.stored.subtitleMode = .always
        let viewModel = AccountPreferencesViewModel(service: service)
        await viewModel.load()

        await viewModel.apply(.selectsAudioByLanguage(false))

        #expect(viewModel.preferences?.selectsAudioByLanguage == false)
        #expect(viewModel.preferences?.subtitleMode == .manual)
    }

    @Test func `a failed change restores the stored value`() async {
        let service = Service()
        let viewModel = AccountPreferencesViewModel(service: service)
        await viewModel.load()
        service.applyError = Failure()

        await viewModel.apply(.audioLanguage("en"))

        #expect(viewModel.preferences?.audioLanguage == "fr")
        #expect(viewModel.saveFailed)
    }

    @Test func `a reload during a write keeps the new value`() async {
        let service = Service()
        let viewModel = AccountPreferencesViewModel(service: service)
        await viewModel.load()
        let (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
        service.beforeApplying = {
            for await _ in release {
                break
            }
        }

        let write = Task { await viewModel.apply(.audioLanguage("en")) }
        while service.appliedChanges.isEmpty {
            await Task.yield()
        }
        await viewModel.load()
        #expect(viewModel.preferences?.audioLanguage == "en")

        releaseContinuation.yield()
        await write.value
        #expect(viewModel.preferences?.audioLanguage == "en")
    }

    @Test func `the same value is not written again`() async {
        let service = Service()
        let viewModel = AccountPreferencesViewModel(service: service)
        await viewModel.load()

        await viewModel.apply(.audioLanguage("fr"))

        #expect(service.appliedChanges.isEmpty)
    }

    @Test func `a stored language outside the list stays selectable`() {
        let viewModel = AccountPreferencesViewModel(service: Service())

        let options = viewModel.languageOptions(selected: "zxx")

        #expect(options.first == .some(nil))
        #expect(options.contains("zxx"))
        #expect(options.contains("fr"))
        #expect(viewModel.languageOptions(selected: "fr").count(where: { $0 == "fr" }) == 1)
    }
}
