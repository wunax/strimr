import SwiftUI

/// Compares the availability only, so that the playback position refreshing the player does not rebuild open pickers.
struct PlayerSubtitleAppearancePanel: View, Equatable {
    static let sideWidth: CGFloat = 340
    static let bottomHeight: CGFloat = 340

    let availability: SubtitleAppearanceAvailability
    let onClose: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.availability == rhs.availability
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("player.settings.subtitles.appearance")
                    .font(.headline)
                Spacer()
                Button("common.actions.done", action: onClose)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            List {
                SubtitleAppearanceSections(availability: availability, showsDescriptions: false)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LayoutMetrics.overlayCornerRadius))
        .environment(\.colorScheme, .dark)
    }
}
