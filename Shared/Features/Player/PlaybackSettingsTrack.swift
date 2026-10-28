import SwiftUI

struct PlaybackSettingsTrack: Identifiable, Hashable {
    let track: PlayerTrack
    let metadata: MediaTrackMetadata?

    var id: Int {
        track.id
    }

    private var metadataCodec: String? {
        metadata?.codec.uppercased()
    }

    private var metadataLabels: [String] {
        var labels: [String] = []
        if track.isDefault {
            labels.append(String(localized: "player.settings.track.default"))
        }
        if track.isForced {
            labels.append(String(localized: "player.settings.track.forced"))
        }
        if track.isHearingImpaired {
            labels.append(String(localized: "player.settings.track.sdh"))
        }
        if track.isCommentary {
            labels.append(String(localized: "player.settings.track.commentary"))
        }
        if track.isExternal {
            labels.append(String(localized: "player.settings.track.external"))
        }
        return labels
    }

    var title: String {
        guard metadata != nil else { return track.displayName }

        if let displayTitle = metadata?.displayTitle, !displayTitle.isEmpty {
            return displayTitle
        }

        return track.displayName
    }

    var subtitle: String? {
        guard let metadata else {
            return combinedSubtitle([track.codec?.uppercased()])
        }

        let codec = metadataCodec.flatMap { title.range(of: $0, options: .caseInsensitive) == nil ? $0 : nil }
        return combinedSubtitle([metadata.secondaryTitle, codec])
    }

    private func combinedSubtitle(_ primary: [String?]) -> String? {
        let values = primary.compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        } + metadataLabels

        guard !values.isEmpty else { return nil }
        return values.joined(separator: " • ")
    }
}

struct PlaybackSettingsVersion: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let isAvailable: Bool
    let isSelected: Bool

    static func options(versions: [MediaFileVersion], selectedID: String?) -> [PlaybackSettingsVersion] {
        let labels = MediaFileVersion.displayLabels(for: versions)
        return versions.enumerated().compactMap { index, version in
            guard let id = version.id else { return nil }
            return PlaybackSettingsVersion(
                id: id,
                title: labels[index],
                subtitle: version.isAvailable
                    ? version.detailLabel
                    : String(localized: "media.versions.unavailable"),
                isAvailable: version.isAvailable,
                isSelected: selectedID.map(version.matchesVersionID) ?? false,
            )
        }
    }
}

struct TrackSelectionRow: View {
    var title: String
    var subtitle: String?
    var isSelected: Bool
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let systemImage {
                    Image(systemName: systemImage)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.selectionAccent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
