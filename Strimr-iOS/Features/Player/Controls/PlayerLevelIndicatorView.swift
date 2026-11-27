import SwiftUI

struct PlayerLevelIndicatorView: View {
    let adjustment: VerticalSwipeAdjustment
    let level: Double

    private var systemImage: String {
        switch adjustment {
        case .brightness: level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume: level <= 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        }
    }

    private var accessibilityLabel: LocalizedStringKey {
        switch adjustment {
        case .brightness: "player.gestures.brightness"
        case .volume: "player.gestures.volume"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage, variableValue: adjustment == .volume ? level : nil)
                .font(.facts.weight(.semibold))
                .frame(width: 24)
                .contentTransition(.symbolEffect(.replace))

            Capsule()
                .fill(.progressTrack)
                .frame(width: 140, height: 6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.progressFill)
                        .frame(width: 140 * level)
                }
        }
        .foregroundStyle(.textPrimary)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .videoOverlayGlass()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(level, format: .percent.precision(.fractionLength(0))))
    }
}
