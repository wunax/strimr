#if !os(tvOS)
    import SwiftUI
    #if os(iOS)
        import UIKit
    #else
        import AppKit
    #endif

    /// Copies the link of a title, for an NFC tag, a home automation or a message.
    struct CopyDeepLinkButton: View {
        @Environment(SessionManager.self) private var sessionManager
        @Environment(ServerRegistry.self) private var registry
        @Environment(ToastCenter.self) private var toastCenter: ToastCenter?

        let media: MediaItem

        var body: some View {
            if DeepLink.shareLink(for: media, profile: nil) != nil {
                Button("deepLinks.copyLink", systemImage: "link") {
                    Task { await copy() }
                }
            }
        }

        /// Cards of a hub may lack the catalog ids that the item's own details carry.
        private func copy() async {
            var media = media
            if media.type == .movie || media.type == .series, media.externalIDs.isEmpty,
               let services = registry.services(for: media.identity.server),
               let detailed = try? await services.detail.mediaItem(id: media.id)
            {
                media = detailed
            }
            guard let link = DeepLink.shareLink(for: media, profile: sessionManager.activeProfile?.id) else { return }
            Self.copyToPasteboard(link.url.absoluteString)
            toastCenter?.show(Toast(style: .success, title: String(localized: "deepLinks.copied")))
        }

        static func copyToPasteboard(_ text: String) {
            #if os(iOS)
                UIPasteboard.general.string = text
            #else
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            #endif
        }
    }
#endif

#if !os(tvOS)
    /// Copies the link that tunes a channel, e.g. `strimr://live/<channel>`.
    struct CopyChannelLinkButton: View {
        @Environment(SessionManager.self) private var sessionManager
        @Environment(MediaServices.self) private var services: MediaServices?
        @Environment(ToastCenter.self) private var toastCenter: ToastCenter?

        let channel: LiveTVChannel

        var body: some View {
            if let services {
                Button("deepLinks.copyLink", systemImage: "link") {
                    let link = DeepLink.liveChannelLink(
                        channel,
                        server: services.identity,
                        profile: sessionManager.activeProfile?.id,
                    )
                    CopyDeepLinkButton.copyToPasteboard(link.url.absoluteString)
                    toastCenter?.show(Toast(style: .success, title: String(localized: "deepLinks.copied")))
                }
            }
        }
    }
#endif
