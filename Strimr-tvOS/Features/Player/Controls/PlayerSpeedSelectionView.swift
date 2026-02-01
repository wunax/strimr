import SwiftUI

struct PlayerSpeedSelectionView: View {
    var selectedRate: Float
    var onSelect: (Float) -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(PlaybackSpeedOptions.all) { option in
                    TrackSelectionRow(
                        title: String(localized: "player.settings.speed.value \(option.valueText)"),
                        subtitle: nil,
                        isSelected: abs(selectedRate - option.rate) < 0.001,
                    ) {
                        onSelect(option.rate)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationTitle("player.settings.speed")
        }
    }
}
