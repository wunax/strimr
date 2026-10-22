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
                Text("seerr.media.availability.requested")
            }
            .font(.badge)
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.9), in: Capsule())
        } else {
            Image(systemName: "paperplane.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(6)
                .background(Color.blue.opacity(0.9), in: Circle())
        }
    }
}
