import SwiftUI

struct SeerrAvailabilityBadgeView: View {
    let status: SeerrMediaStatus
    var showsLabel = false
    var isDownloading = false

    var body: some View {
        if let configuration {
            // Same dark badge as the watch status of library cards; only the icon carries the status color.
            if showsLabel {
                HStack(spacing: 4) {
                    Image(systemName: configuration.systemName)
                        .foregroundStyle(configuration.color)
                    Text(configuration.labelKey)
                        .foregroundStyle(.textPrimary)
                }
                .font(.badge)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.badgeBackground, in: Capsule(style: .continuous))
            } else {
                Image(systemName: configuration.systemName)
                    .font(.badge)
                    .foregroundStyle(configuration.color)
                    .padding(6)
                    .background(.badgeBackground, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
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
        case .processing where isDownloading:
            AvailabilityConfiguration(
                systemName: "arrow.triangle.2.circlepath.circle.fill",
                color: .yellow,
                labelKey: "seerr.media.availability.processing",
            )
        case .processing:
            AvailabilityConfiguration(
                systemName: "clock.fill",
                color: .yellow,
                labelKey: "seerr.media.availability.requested",
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
