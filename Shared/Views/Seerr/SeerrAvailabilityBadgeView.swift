import SwiftUI

struct SeerrAvailabilityBadgeView: View {
    let status: SeerrMediaStatus
    var showsLabel = false

    var body: some View {
        if let configuration {
            if showsLabel {
                HStack(spacing: 4) {
                    Image(systemName: configuration.systemName)
                    Text(configuration.labelKey)
                }
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(configuration.color.opacity(0.9), in: Capsule())
            } else {
                Image(systemName: configuration.systemName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(configuration.color.opacity(0.9), in: Circle())
            }
        }
    }

    private var configuration: AvailabilityConfiguration? {
        switch status {
        case .available:
            AvailabilityConfiguration(
                systemName: "checkmark.circle.fill",
                color: .green,
                labelKey: "seerr.media.availability.available",
            )
        case .partiallyAvailable:
            AvailabilityConfiguration(
                systemName: "minus.circle.fill",
                color: .green,
                labelKey: "seerr.media.availability.partiallyAvailable",
            )
        case .processing:
            AvailabilityConfiguration(
                systemName: "arrow.triangle.2.circlepath.circle.fill",
                color: .yellow,
                labelKey: "seerr.media.availability.processing",
            )
        case .pending:
            AvailabilityConfiguration(
                systemName: "clock.fill",
                color: .yellow,
                labelKey: "seerr.media.availability.pending",
            )
        case .blacklisted, .deleted:
            AvailabilityConfiguration(
                systemName: "xmark.octagon.fill",
                color: .red,
                labelKey: "seerr.media.availability.unavailable",
            )
        case .unknown:
            nil
        }
    }
}

private struct AvailabilityConfiguration {
    let systemName: String
    let color: Color
    let labelKey: LocalizedStringKey
}
