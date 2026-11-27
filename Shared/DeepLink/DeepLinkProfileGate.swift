import SwiftUI

/// Applies the profile a link names before the link is handled. It sits above the main view, which is rebuilt when
/// the profile changes.
enum DeepLinkProfileGate {
    enum Decision: Equatable {
        /// Session not settled yet: decide again when it is.
        case wait
        case proceed
        case drop
        case profileNotFound
        case activate(String)
        /// The profile has a PIN: the picker asks for it.
        case askForPIN(String)
    }

    /// Matches the profile id first, then its name ignoring case.
    static func profile(named reference: String, in profiles: [StrimrProfile]) -> StrimrProfile? {
        profiles.first { $0.id == reference }
            ?? profiles
            .first { $0.name.compare(reference, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
    }

    static func requiresPIN(_ profile: StrimrProfile) -> Bool {
        switch profile {
        case let .local(local): local.pin != nil
        case let .plexHome(home): home.user.protected ?? false
        }
    }

    static func decide(
        reference: String,
        profiles: [StrimrProfile],
        activeProfileID: String?,
        status: SessionManager.Status,
        awaitedProfileID: String?,
    ) -> Decision {
        switch status {
        case .hydrating, .migrationFailed:
            return .wait
        case .needsAccount:
            return .drop
        case .needsProfileSelection, .ready:
            break
        }
        guard let profile = profile(named: reference, in: profiles) else { return .profileNotFound }
        if let awaitedProfileID {
            // The picker is open for this link: wait for the user, and drop the link if they picked another profile.
            guard status == .ready else { return .wait }
            return activeProfileID == awaitedProfileID ? .proceed : .drop
        }
        if status == .ready, activeProfileID == profile.id {
            return .proceed
        }
        return requiresPIN(profile) ? .askForPIN(profile.id) : .activate(profile.id)
    }
}

extension View {
    func appliesDeepLinkProfiles() -> some View {
        modifier(DeepLinkProfileModifier())
    }
}

private struct DeepLinkProfileModifier: ViewModifier {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(DeepLinkRouter.self) private var router
    @Environment(ToastCenter.self) private var toastCenter: ToastCenter?

    private struct Key: Equatable {
        let link: DeepLink?
        let status: SessionManager.Status
        let activeProfileID: String?
    }

    func body(content: Content) -> some View {
        content.task(id: Key(
            link: router.pending,
            status: sessionManager.status,
            activeProfileID: sessionManager.activeProfile?.id,
        )) {
            await apply()
        }
    }

    private func apply() async {
        guard let link = router.pending, let reference = link.profile else { return }
        let decision = DeepLinkProfileGate.decide(
            reference: reference,
            profiles: sessionManager.profiles,
            activeProfileID: sessionManager.activeProfile?.id,
            status: sessionManager.status,
            awaitedProfileID: router.awaitedProfileID,
        )
        switch decision {
        case .wait:
            return
        case .proceed:
            router.resolveProfile(of: link)
        case .drop:
            router.clear(link)
        case .profileNotFound:
            router.clear(link)
            toastCenter?.show(Toast(style: .failure, title: String(localized: "deepLinks.profileNotFound")))
        case let .askForPIN(profileID):
            askForPIN(profileID, link: link)
        case let .activate(profileID):
            guard let profile = sessionManager.profiles.first(where: { $0.id == profileID }) else { return }
            do {
                try await sessionManager.activateWithoutPIN(profile)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                // Plex may still want a PIN, or plex.tv did not answer: the picker lets the user try.
                askForPIN(profileID, link: link)
            }
        }
    }

    private func askForPIN(_ profileID: String, link: DeepLink) {
        guard router.pending == link else { return }
        router.awaitedProfileID = profileID
        sessionManager.requestProfileSelection(preferring: profileID)
    }
}
