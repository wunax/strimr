import SwiftUI

/// 48 pt round icon with a short caption; filled icon and full-white caption when the state is on.
struct DetailRoundActionLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: LocalizedStringKey
    let systemImage: String
    let isActive: Bool
    let isLoading: Bool
    /// Replaces the loading spinner with a ring and percentage when the work reports how far it is.
    var progress: Double?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.surfaceRaised)
                if isLoading, let progress {
                    DownloadProgressRing(progress: progress, lineWidth: 3)
                } else if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isActive ? .textPrimary : .textSecondary)
                }
            }
            .frame(width: 48, height: 48)

            Text(title)
                .font(.cardMetadata)
                .foregroundStyle(isActive ? .textPrimary : .textSecondary)
                .lineLimit(1)
        }
        .frame(minWidth: 56)
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(Rectangle())
        .accessibilityValue(progressValue)
    }

    private var progressValue: Text {
        guard isLoading, let progress else { return Text(verbatim: "") }
        return Text(progress, format: .percent.precision(.fractionLength(0)))
    }
}
