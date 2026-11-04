import Observation
import SwiftUI

@MainActor
@Observable
final class AccountPreferencesViewModel {
    private(set) var preferences: AccountPreferences?
    private(set) var loadFailed = false
    var saveFailed = false

    @ObservationIgnored private let service: any AccountPreferencesService
    @ObservationIgnored private var confirmed: AccountPreferences?
    @ObservationIgnored private var writeGeneration = 0
    @ObservationIgnored private var pendingWrites = 0

    init(service: any AccountPreferencesService) {
        self.service = service
    }

    var subtitleModes: [AccountSubtitleMode] {
        service.subtitleModes
    }

    func load() async {
        loadFailed = false
        let generation = writeGeneration
        do {
            let loaded = try await service.load()
            // Coming back from a picker reloads while its write is running: this answer can predate the write.
            guard pendingWrites == 0, generation == writeGeneration else { return }
            confirmed = loaded
            preferences = loaded
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            report(error)
            loadFailed = true
        }
    }

    func apply(_ change: AccountPreferenceChange) async {
        guard let preferences, preferences.applying(change) != preferences else { return }
        writeGeneration += 1
        pendingWrites += 1
        defer { pendingWrites -= 1 }
        let generation = writeGeneration
        self.preferences = preferences.applying(change)
        do {
            let updated = try await service.apply(change)
            confirmed = updated
            guard generation == writeGeneration else { return }
            self.preferences = updated
        } catch {
            guard generation == writeGeneration else { return }
            self.preferences = confirmed
            guard !Task.isCancelled, !error.isCancellation else { return }
            report(error)
            saveFailed = true
        }
    }

    /// Options of a language picker: no preference first, then every ISO 639-1 language by name. A stored code outside
    /// that list stays selectable, otherwise the picker would have nothing to show as selected.
    func languageOptions(selected: String?) -> [String?] {
        let codes = Self.languageCodes
        let extra = selected.flatMap { codes.contains($0) ? nil : $0 }
        return [nil] + (extra.map { [$0] } ?? []) + codes
    }

    func languageTitle(_ code: String?) -> String {
        code.map(AccountLanguageCode.displayName)
            ?? String(localized: "settings.accountPreferences.noPreference")
    }

    var audioLanguage: Binding<String?> {
        binding(\.audioLanguage, change: AccountPreferenceChange.audioLanguage)
    }

    var selectsAudioByLanguage: Binding<Bool> {
        binding(\.selectsAudioByLanguage, change: AccountPreferenceChange.selectsAudioByLanguage)
    }

    var subtitleLanguage: Binding<String?> {
        binding(\.subtitleLanguage, change: AccountPreferenceChange.subtitleLanguage)
    }

    var subtitleMode: Binding<AccountSubtitleMode> {
        binding(\.subtitleMode, change: AccountPreferenceChange.subtitleMode)
    }

    private func binding<Value>(
        _ keyPath: KeyPath<AccountPreferences, Value>,
        change: @escaping (Value) -> AccountPreferenceChange,
    ) -> Binding<Value> {
        Binding(
            get: { (self.preferences ?? .empty)[keyPath: keyPath] },
            set: { value in
                Task { await self.apply(change(value)) }
            },
        )
    }

    private func report(_ error: any Error) {
        guard !error.isTransportFailure, !error.isAuthenticationFailure else { return }
        ErrorReporter.capture(error)
    }

    private static let languageCodes = SubtitleLanguageOption.all
        .filter { $0.code.count == 2 }
        .map(\.code)
}
