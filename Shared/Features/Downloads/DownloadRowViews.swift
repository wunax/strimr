import SwiftUI

struct DownloadsStorageSummaryView: View {
    let summary: DownloadStorageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("downloads.storage.title")
                .font(.cardTitle)
                .foregroundStyle(.textPrimary)

            usageBar

            VStack(alignment: .leading, spacing: 2) {
                Text("downloads.storage.downloads \(formattedBytes(summary.downloadsBytes))")
                Text(
                    "downloads.storage.device \(formattedBytes(summary.usedBytes)) \(formattedBytes(summary.totalBytes))",
                )
            }
            .font(.facts)
            .foregroundStyle(.textSecondary)
        }
        .padding(.vertical, 4)
    }

    /// Downloads drawn over the rest of the used space, both on the device capacity.
    private var usageBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color.progressTrack
                Color.progressBuffered
                    .frame(width: proxy.size.width * fraction(of: summary.usedBytes))
                Color.progressFill
                    .frame(width: proxy.size.width * fraction(of: summary.downloadsBytes))
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private func fraction(of bytes: Int64) -> CGFloat {
        guard summary.totalBytes > 0 else { return 0 }
        return min(max(CGFloat(bytes) / CGFloat(summary.totalBytes), 0), 1)
    }
}

struct DownloadsOfflineBanner: View {
    var body: some View {
        Label("offline.banner.offline", systemImage: "wifi.slash")
            .font(.facts.weight(.semibold))
            .foregroundStyle(.orange)
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    let posterURL: URL?
    let isSpoilerProtected: Bool
    var isWaitingForWiFi = false
    var onUseCellular: (() -> Void)?
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            poster
                .frame(width: posterWidth, height: posterWidth * 1.5)
                .mediaArtworkStyle(.compact)
                .overlay(alignment: .topLeading) {
                    if isSpoilerProtected {
                        SpoilerProtectionIndicator()
                            .padding(5)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.metadata.title)
                    .font(.cardTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(2)

                if let subtitle = item.metadata.subtitle {
                    Text(subtitle)
                        .font(.cardMetadata)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                }

                Text(verbatim: [item.metadata.versionLabel, item.metadata.effectiveQuality.title]
                    .compactMap(\.self)
                    .joined(separator: " · "))
                    .font(.cardMetadata)
                    .foregroundStyle(.textTertiary)

                status
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            #if os(macOS)
                if item.isPlayable {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.textSecondary)
                }
            #endif
        }
        .padding(.vertical, 4)
    }

    private var posterWidth: CGFloat {
        #if os(macOS)
            72
        #else
            64
        #endif
    }

    @ViewBuilder
    private var poster: some View {
        if !isSpoilerProtected, let image = posterURL.flatMap(Self.localImage(at:)) {
            image
                .resizable()
                .scaledToFill()
        } else {
            MediaArtworkPlaceholder(mediaKind: item.metadata.type)
        }
    }

    private static func localImage(at url: URL) -> Image? {
        #if os(macOS)
            NSImage(contentsOf: url).map(Image.init(nsImage:))
        #else
            UIImage(contentsOfFile: url.path).map(Image.init(uiImage:))
        #endif
    }

    @ViewBuilder
    private var status: some View {
        switch item.status {
        case .queued:
            statusText("downloads.status.queued")
        case .preparing:
            progress(label: "downloads.status.preparing \(percent)")
        case .downloading:
            if isWaitingForWiFi {
                waitingForWiFi
            } else {
                progress(label: "downloads.status.downloading \(percent)")
            }
        case .completed:
            statusText("downloads.status.completed \(formattedBytes(item.metadata.fileSize ?? item.totalBytes))")
        case .failed:
            VStack(alignment: .leading, spacing: 4) {
                Text(item.errorMessage ?? String(localized: "downloads.status.failed"))
                    .font(.cardMetadata)
                    .foregroundStyle(.red)
                    .lineLimit(2)

                if let onRetry {
                    Button(action: onRetry) {
                        Label("common.actions.retry", systemImage: "arrow.clockwise")
                            .font(.cardMetadata.weight(.semibold))
                        #if os(iOS)
                            .frame(minHeight: 44)
                        #endif
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.textPrimary)
                    .accessibilityHint(Text(verbatim: item.metadata.title))
                }
            }
        }
    }

    private var percent: Int {
        Int((item.progress * 100).rounded())
    }

    private func statusText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.cardMetadata)
            .foregroundStyle(.textSecondary)
    }

    private func progress(label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: item.progress)
                .tint(.progressFill)
            statusText(label)
        }
    }

    private var waitingForWiFi: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("downloads.status.waitingForWiFi", systemImage: "wifi")
                .font(.cardMetadata)
                .foregroundStyle(.textSecondary)

            Text("downloads.status.waitingForWiFi.description")
                .font(.cardMetadata)
                .foregroundStyle(.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let onUseCellular {
                Button(action: onUseCellular) {
                    Label("downloads.action.cellular", systemImage: "cellularbars")
                        .font(.cardMetadata.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(.textPrimary)
                .padding(.top, 2)
            }
        }
    }
}

private func formattedBytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}
