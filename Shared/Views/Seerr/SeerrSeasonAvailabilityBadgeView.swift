import SwiftUI

struct SeerrSeasonAvailabilityBadgeView: View {
    let badge: SeerrSeasonAvailabilityBadge
    var showsLabel = false
    var isDownloading = false

    var body: some View {
        switch badge {
        case let .media(status):
            SeerrAvailabilityBadgeView(status: status, showsLabel: showsLabel, isDownloading: isDownloading)
        case let .request(status):
            switch status {
            case .pending:
                SeerrAvailabilityBadgeView(status: .pending, showsLabel: showsLabel)
            case .approved:
                requestBadge
            case .declined, .failed, .completed:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var requestBadge: some View {
        if showsLabel {
            HStack(spacing: 4) {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(.blue)
                Text("seerr.media.availability.requested")
                    .foregroundStyle(.textPrimary)
            }
            .font(.badge)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.badgeBackground, in: Capsule(style: .continuous))
        } else {
            Image(systemName: "paperplane.fill")
                .font(.badge)
                .foregroundStyle(.blue)
                .padding(6)
                .background(.badgeBackground, in: Circle())
        }
    }
}
