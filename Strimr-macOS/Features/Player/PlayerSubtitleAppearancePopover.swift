import SwiftUI

struct PlayerSubtitleAppearancePopover: View {
    let availability: SubtitleAppearanceAvailability

    var body: some View {
        Form {
            SubtitleAppearanceSections(availability: availability, showsDescriptions: false)
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 440)
    }
}
