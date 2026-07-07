import SwiftUI

struct PlaybackSettingsTrack: Identifiable, Hashable {
    let track: PlayerTrack
    let plexStream: PlexPartStream?

    var id: Int {
        track.id
    }

    private var plexCodec: String? {
        plexStream?.codec.uppercased()
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
        guard plexStream != nil else { return track.displayName }

        if let plexDisplayTitle = plexStream?.displayTitle, !plexDisplayTitle.isEmpty {
            switch track.type {
            case .subtitle:
                if let plexCodec {
                    return "\(plexDisplayTitle) (\(plexCodec))"
                }
                return plexDisplayTitle
            default:
                return plexDisplayTitle
            }
        }

        return track.displayName
    }

    var subtitle: String? {
        guard plexStream != nil else {
            return combinedSubtitle(track.codec?.uppercased())
        }

        if let plexTitle = plexStream?.title, !plexTitle.isEmpty {
            return combinedSubtitle(plexTitle)
        }

        return combinedSubtitle(plexCodec ?? track.codec?.uppercased())
    }

    private func combinedSubtitle(_ primary: String?) -> String? {
        let values = [primary].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        } + metadataLabels

        guard !values.isEmpty else { return nil }
        return values.joined(separator: " • ")
    }
}

struct TrackSelectionRow: View {
    var title: String
    var subtitle: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
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
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
