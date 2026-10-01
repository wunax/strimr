import SwiftUI

struct MediaVersionSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        PlayerSettingsOptionsView(
            title: "media.versions.title",
            options: options,
            onClose: { dismiss() },
        )
        .frame(maxWidth: 1100)
        .padding(.horizontal, 48)
    }

    private var options: [PlayerSettingsOption] {
        let labels = viewModel.versionLabels
        let automatic = PlayerSettingsOption(
            id: "automatic",
            title: String(localized: "media.versions.automatic"),
            subtitle: viewModel.automaticVersion?.displayLabel(among: viewModel.versions),
            isSelected: !viewModel.hasVersionPreference,
            action: { select(nil) },
        )
        let versions = viewModel.versions.enumerated().map { index, version in
            PlayerSettingsOption(
                id: version.id ?? "version.\(index)",
                title: labels[index],
                subtitle: version.isAvailable ? version.detailLabel : String(localized: "media.versions.unavailable"),
                isSelected: viewModel.hasVersionPreference
                    && (viewModel.selectedVersionID.map(version.matchesVersionID) ?? false),
                isDisabled: !version.isAvailable || version.id == nil,
                action: { select(version.id) },
            )
        }
        return [automatic] + versions
    }

    private func select(_ versionID: String?) {
        Task {
            await viewModel.selectVersion(id: versionID)
            dismiss()
        }
    }
}
