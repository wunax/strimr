import SwiftUI

struct HeroMaskView: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.25),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.25),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .trailing,
                endPoint: .leading,
            ),
        )
    }
}
