#if !os(tvOS)
    import CoreSpotlight
    import SwiftUI

    /// Handoff between iPhone, iPad and Mac. An activity only carries a link: the device that continues reads the
    /// progress saved on the server.
    enum Handoff {
        static let mediaActivityType = "com.github.wunax.strimr.media"
        static let playbackActivityType = "com.github.wunax.strimr.playback"
        static let linkKey = "link"

        static func link(from activity: NSUserActivity) -> URL? {
            if activity.activityType == CSSearchableItemActionType {
                return (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(URL.init(string:))
            }
            return (activity.userInfo?[linkKey] as? String).flatMap(URL.init(string:))
        }
    }

    extension View {
        /// Offers the title shown on the page to the user's other devices.
        func handoffMedia(_ media: MediaItem?) -> some View {
            advertising(
                Handoff.mediaActivityType,
                media: media,
                link: media.map { DeepLink(.media(.item($0.identity, kind: $0.type))) },
            )
        }

        /// Offers the title playing to the user's other devices, which resume it.
        func handoffPlayback(_ media: MediaItem?) -> some View {
            advertising(
                Handoff.playbackActivityType,
                media: media,
                link: media.map { DeepLink(.play(.item($0.identity, kind: $0.type), mode: .resume)) },
            )
        }

        private func advertising(_ type: String, media: MediaItem?, link: DeepLink?) -> some View {
            userActivity(type, isActive: link != nil) { activity in
                guard let media, let link else { return }
                activity.title = media.primaryLabel
                activity.userInfo = [Handoff.linkKey: link.url.absoluteString]
                activity.isEligibleForHandoff = true
                #if os(iOS)
                    activity.isEligibleForPrediction = true
                #endif
                activity.isEligibleForSearch = false
            }
        }

        /// Opens what another device or Spotlight hands over.
        func continuesUserActivities() -> some View {
            onContinueUserActivity(Handoff.mediaActivityType, perform: continueActivity)
                .onContinueUserActivity(Handoff.playbackActivityType, perform: continueActivity)
                .onContinueUserActivity(CSSearchableItemActionType, perform: continueActivity)
        }
    }

    @MainActor
    private func continueActivity(_ activity: NSUserActivity) {
        guard let url = Handoff.link(from: activity) else { return }
        DeepLinkRouter.shared.receive(url)
    }
#endif
