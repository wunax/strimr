import SwiftUI

/// Player controls styled after the tvOS system player: a thin timeline at the bottom, the title above it, round
/// glass buttons on the right and tabs below.
struct SystemPlayerControlsView: View {
    var state: PlayerControlsState
    var actions: PlayerControlsActions
    @Binding var position: Double

    var body: some View {
        Color.clear
    }
}
