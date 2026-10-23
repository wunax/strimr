import SwiftUI

@MainActor
struct SeerrRequestCardView: View {
    let viewModel: SeerrRequestsViewModel
    let request: SeerrRequest
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    poster
                    details
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif
            .disabled(viewModel.openableMedia(for: request) == nil)

            if hasActions {
                actions
            }
        }
        .padding(cardPadding)
        .background(
            .surfaceSubtle,
            in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous),
        )
    }

    private var posterSize: CGSize {
        #if os(tvOS)
            CGSize(width: 140, height: 210)
        #else
            CGSize(width: 100, height: 150)
        #endif
    }

    private var cardPadding: CGFloat {
        #if os(tvOS)
            24
        #else
            12
        #endif
    }

    private var poster: some View {
        let media = viewModel.mediaDetail(for: request)
        return AsyncImage(url: TMDBImageService.posterURL(
            path: media?.posterPath,
            width: posterSize.width * 2,
        )) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Color.surfaceSubtle
            }
        }
        .frame(width: posterSize.width, height: posterSize.height)
        .mediaArtworkStyle()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let year = viewModel.mediaYear(for: request) {
                    Text(year)
                }
                Text(typeKey)
                    .textCase(.uppercase)
                if request.is4k == true {
                    Text("seerr.manageRequests.badge.4k")
                }
            }
            .eyebrowStyle()
            .foregroundStyle(.textTertiary)
            .lineLimit(1)

            Text(viewModel.mediaTitle(for: request))
                .font(.cardTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(2)

            statusBadge

            if let seasons = viewModel.seasonSummary(for: request) {
                Label(seasons, systemImage: "rectangle.stack")
                    .font(.cardMetadata)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }

            userLine(
                titleKey: "seerr.requests.requestedBy",
                user: request.requestedBy,
                date: request.createdAt,
            )

            if viewModel.showsModified(request) {
                userLine(
                    titleKey: "seerr.requests.modifiedBy",
                    user: request.modifiedBy,
                    date: request.updatedAt,
                )
            }

            if let profile = request.profileName, !profile.isEmpty {
                Text(String(localized: "seerr.manageRequests.profile \(profile)"))
                    .font(.cardMetadata)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var typeKey: LocalizedStringKey {
        viewModel.isTV(request) ? "seerr.media.badge.tv" : "seerr.media.badge.movie"
    }

    private var statusBadge: some View {
        let status = viewModel.displayStatus(for: request)
        let style = Self.style(for: status)
        // Same dark badge as the availability of Seerr media; only the icon carries the status color.
        return HStack(spacing: 4) {
            Image(systemName: style.systemName)
                .foregroundStyle(style.color)
            Text(LocalizedStringKey(status.labelKey))
            if case let .processing(progress) = status, let progress {
                Text("\(Int(progress * 100))%")
            }
        }
        .font(.badge)
        .lineLimit(1)
        .foregroundStyle(.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.badgeBackground, in: Capsule(style: .continuous))
    }

    private func userLine(titleKey: LocalizedStringKey, user: SeerrUser?, date: String?) -> some View {
        HStack(spacing: 6) {
            avatar(for: user)
            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.displayName(for: user))
                    .font(.cardMetadata.weight(.semibold))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(titleKey)
                    if let relative = viewModel.relativeDateText(from: date) {
                        Text(relative)
                    }
                }
                .font(.cardMetadata)
                .foregroundStyle(.textTertiary)
                .lineLimit(1)
            }
        }
    }

    private func avatar(for user: SeerrUser?) -> some View {
        AsyncImage(url: viewModel.avatarURL(for: user)) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Color.surfaceSubtle
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
    }

    private var hasActions: Bool {
        viewModel.canModerate(request) || viewModel.canRetry(request)
            || viewModel.canEdit(request) || viewModel.canDelete(request)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if viewModel.canModerate(request) {
                Button {
                    Task { await viewModel.approve(request) }
                } label: {
                    Label("seerr.requests.action.approve", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    Task { await viewModel.decline(request) }
                } label: {
                    Label("seerr.requests.action.decline", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            if viewModel.canRetry(request) {
                Button {
                    Task { await viewModel.retry(request) }
                } label: {
                    Label("seerr.requests.action.retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            if viewModel.canEdit(request) || viewModel.canDelete(request) {
                Menu {
                    if viewModel.canEdit(request) {
                        Button("seerr.requests.action.edit", systemImage: "square.and.pencil", action: onEdit)
                    }
                    if viewModel.canDelete(request) {
                        Button(role: .destructive, action: onDelete) {
                            Label {
                                Text("seerr.requests.action.delete")
                            } icon: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                        }
                        .tint(.red)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .accessibilityLabel(Text("seerr.requests.action.more"))
            }
        }
        .font(.facts.weight(.semibold))
        .buttonBorderShape(.capsule)
        .disabled(viewModel.isBusy(request))
        .overlay {
            if viewModel.isBusy(request) {
                ProgressView()
            }
        }
    }

    private struct StatusStyle {
        let systemName: String
        let color: Color
    }

    private static func style(for status: SeerrRequestDisplayStatus) -> StatusStyle {
        switch status {
        case .pending:
            StatusStyle(systemName: "clock.fill", color: .orange)
        case .declined, .failed, .blacklisted, .deleted:
            StatusStyle(systemName: "xmark.circle.fill", color: .red)
        case .requested:
            StatusStyle(systemName: "tray.and.arrow.down.fill", color: .indigo)
        case .processing:
            StatusStyle(systemName: "arrow.triangle.2.circlepath.circle.fill", color: .indigo)
        case .partiallyAvailable:
            StatusStyle(systemName: "minus.circle.fill", color: .green)
        case .available:
            StatusStyle(systemName: "checkmark.circle.fill", color: .green)
        }
    }
}
