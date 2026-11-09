import Foundation
import Observation

/// The per-item server settings of the Manage menu. Each choice is applied on the server right away.
@MainActor
@Observable
final class ItemSettingsViewModel: Identifiable {
    struct Failure: Identifiable {
        let id = UUID()
        let message: String
    }

    let item: MediaItem
    private(set) var settings: [ItemSetting]?
    private(set) var errorMessage: String?
    /// The setting being saved, whose picker is disabled meanwhile.
    private(set) var updatingSettingID: String?
    var failure: Failure?
    /// Bumped after each change applied on the server.
    private(set) var changeCount = 0

    @ObservationIgnored private let service: any MediaManagementService
    @ObservationIgnored private let onChange: (String) -> Void

    init(item: MediaItem, service: any MediaManagementService, onChange: @escaping (String) -> Void) {
        self.item = item
        self.service = service
        self.onChange = onChange
    }

    func load() async {
        errorMessage = nil
        do {
            let settings = try await service.advancedSettings(itemID: item.id)
            guard !Task.isCancelled else { return }
            self.settings = settings
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            errorMessage = message(for: error)
        }
    }

    func update(_ setting: ItemSetting, to value: String) async {
        guard updatingSettingID == nil, setting.value != value else { return }
        updatingSettingID = setting.id
        defer { updatingSettingID = nil }
        do {
            try await service.updateAdvancedSetting(setting, value: value, itemID: item.id)
            if let index = settings?.firstIndex(where: { $0.id == setting.id }) {
                settings?[index].value = value
            }
            changeCount += 1
            onChange(item.id)
        } catch {
            guard !error.isCancellation else { return }
            failure = Failure(message: message(for: error))
        }
    }

    /// Captures unexpected failures; a refusal is the server's answer to a right lost meanwhile.
    private func message(for error: Error) -> String {
        guard !error.isManagementRefusal else { return String(localized: "media.manage.error.forbidden") }
        ErrorReporter.capture(error)
        return error.localizedDescription
    }
}
