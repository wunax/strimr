import SwiftUI

@MainActor
struct SeerrRequestCardView: View {
    let viewModel: SeerrRequestsViewModel
    let request: SeerrRequest
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        #if os(tvOS)
            // The focusable card cannot hold other buttons, so the actions sit in a column beside it.
            HStack(alignment: .center, spacing: 32) {
                openButton
                if hasActions {
                    actions
                        .frame(width: 320)
                }
            }
            .focusSection()
        #else
            VStack(alignment: .leading, spacing: 12) {
                openButton
                if hasPrimaryActions {
                    actions
                }
            }
            .padding(cardPadding)
            .background { backdrop }
            .clipShape(cardShape)
            .overlay(alignment: .topTrailing) {
                if hasMenu {
                    moreMenu
                        .padding(8)
                }
            }
        #endif
    }

    private var openButton: some View {
        Button(action: onOpen) {
            summary
            #if os(tvOS)
                .padding(cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { backdrop }
                .clipShape(cardShape)
            #endif
                .contentShape(Rectangle())
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .disabled(viewModel.openableMedia(for: request) == nil)
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: cardPadding) {
            poster
            details
            #if !os(tvOS)
                .padding(.trailing, hasMenu ? 36 : 0)
            #endif
            Spacer(minLength: 0)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
    }

    private var posterSize: CGSize {
        #if os(tvOS)
            CGSize(width: 140, height: 210)
        #else
            CGSize(width: 80, height: 120)
        #endif
    }

    private var cardPadding: CGFloat {
        #if os(tvOS)
            24
        #else
            12
        #endif
    }

    private var detailSpacing: CGFloat {
        #if os(tvOS)
            10
        #else
            6
        #endif
    }

    private var backdrop: some View {
        let media = viewModel.mediaDetail(for: request)
        return ZStack {
            Color.surfaceSubtle
            AsyncImage(url: TMDBImageService.backdropURL(path: media?.backdropPath, width: 1280)) { phase in
                if case let .success(image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .overlay {
                            // Darkest behind the text, lighter on the trailing side so the artwork shows through.
                            LinearGradient(
                                colors: [.black.opacity(0.9), .black.opacity(0.7), .black.opacity(0.45)],
                                startPoint: .leading,
                                endPoint: .trailing,
                            )
                        }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        VStack(alignment: .leading, spacing: detailSpacing) {
            HStack(spacing: 6) {
                if let year = viewModel.mediaYear(for: request) {
                    Text(year)
                    Text(verbatim: "·")
                }
                Text(typeKey)
            }
            .eyebrowStyle()
            .foregroundStyle(.textSecondary)
            .lineLimit(1)

            Text(viewModel.mediaTitle(for: request))
                .font(.rowTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                statusBadge
                if request.is4k == true {
                    Text("seerr.manageRequests.badge.4k")
                        .font(.badge)
                        .foregroundStyle(.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.badgeBackground, in: Capsule(style: .continuous))
                }
            }

            if let facts = factsText {
                Text(facts)
                    .font(.cardMetadata)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }

            requesterLine
                .padding(.top, detailSpacing / 2)

            if viewModel.showsModified(request) {
                modifiedLine
            }
        }
    }

    private var typeKey: LocalizedStringKey {
        viewModel.isTV(request) ? "seerr.media.badge.tv" : "seerr.media.badge.movie"
    }

    private var factsText: String? {
        var parts: [String] = []
        if let seasons = viewModel.seasonSummary(for: request) {
            parts.append(seasons)
        }
        if let profile = request.profileName, !profile.isEmpty {
            parts.append(String(localized: "seerr.manageRequests.profile \(profile)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

    private var requesterLine: some View {
        HStack(spacing: 8) {
            avatar(for: request.requestedBy)
            Text(viewModel.displayName(for: request.requestedBy))
                .fontWeight(.semibold)
                .foregroundStyle(.textPrimary)
                .layoutPriority(1)
            activityText(titleKey: "seerr.requests.requestedBy", date: request.createdAt)
        }
        .font(.cardMetadata)
        .lineLimit(1)
    }

    private var modifiedLine: some View {
        HStack(spacing: 4) {
            activityText(titleKey: "seerr.requests.modifiedBy", date: request.updatedAt)
            Text(verbatim: "·")
                .foregroundStyle(.textTertiary)
            Text(viewModel.displayName(for: request.modifiedBy))
                .foregroundStyle(.textSecondary)
        }
        .font(.cardMetadata)
        .lineLimit(1)
    }

    private func activityText(titleKey: LocalizedStringKey, date: String?) -> some View {
        HStack(spacing: 4) {
            Text(titleKey)
            if let relative = viewModel.relativeDateText(from: date) {
                Text(relative)
            }
        }
        .foregroundStyle(.textTertiary)
    }

    private var avatarSize: CGFloat {
        #if os(tvOS)
            32
        #else
            20
        #endif
    }

    private func avatar(for user: SeerrUser?) -> some View {
        AsyncImage(url: viewModel.avatarURL(for: user)) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.textTertiary)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
    }

    private var hasPrimaryActions: Bool {
        viewModel.canModerate(request) || viewModel.canRetry(request)
    }

    private var hasMenu: Bool {
        viewModel.canEdit(request) || viewModel.canDelete(request)
    }

    private var hasActions: Bool {
        hasPrimaryActions || hasMenu
    }

    private var actions: some View {
        actionsLayout {
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

            #if os(tvOS)
                if hasMenu {
                    moreMenu
                }
            #endif
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

    private func actionsLayout(@ViewBuilder content: () -> some View) -> some View {
        #if os(tvOS)
            VStack(spacing: 16) {
                content()
            }
        #else
            HStack(spacing: 8) {
                content()
            }
        #endif
    }

    private var moreMenu: some View {
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
            #if os(tvOS)
                Label("seerr.requests.action.more", systemImage: "ellipsis")
                    .font(.facts.weight(.semibold))
                    .frame(maxWidth: .infinity)
            #else
                Image(systemName: "ellipsis")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(.badgeBackground, in: Circle())
                    .contentShape(Circle())
            #endif
        }
        #if os(tvOS)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        #else
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        #endif
        .disabled(viewModel.isBusy(request))
        .accessibilityLabel(Text("seerr.requests.action.more"))
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
