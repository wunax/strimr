import SwiftUI

struct PlayerControlsView: View {
    @Binding var position: Double
    var duration: Double?
    var onEditingChanged: (Bool) -> Void
    
    private var sliderUpperBound: Double {
        max(duration ?? 0, position, 1)
    }
    
    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                min(position, sliderUpperBound)
            },
            set: { newValue in
                position = newValue
            }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Slider(value: sliderBinding, in: 0...sliderUpperBound, onEditingChanged: onEditingChanged)
                .tint(.white)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        PlayerControlsView(position: .constant(15), duration: 60) { _ in }
    }
}
