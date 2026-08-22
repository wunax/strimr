import SwiftUI

struct PlayerQualitySelectionView: View {
    var selectedQuality: TranscodeQualityPreset
    var onSelect: (TranscodeQualityPreset) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(TranscodeQualityPreset.displayOrder) { preset in
                    TrackSelectionRow(
                        title: preset.title,
                        subtitle: nil,
                        isSelected: selectedQuality == preset,
                    ) {
                        onSelect(preset)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationTitle("player.settings.quality")
        }
    }
}
