import SwiftUI

/// Round glass button of the system style that opens an anchored menu. The menu is drawn by Strimr rather than by
/// SwiftUI's `Menu`, which on tvOS took the focus out of the player: a click could miss the menu and reach the system
/// as play/pause, and Back could leave the app. Everything about menus stays in this file.
enum SystemPlayerMenu: Hashable {
    case subtitles
    case audio
    case more
}

struct SystemPlayerMenuButton: View {
    var systemImage: String
    var accessibilityLabel: String
    var menu: SystemPlayerMenu
    @Binding var presentedMenu: SystemPlayerMenu?
    var showsIndicator = false

    var body: some View {
        Button {
            presentedMenu = menu
        } label: {
            SystemPlayerButtonLabel(systemImage: systemImage)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .overlay(alignment: .topTrailing) {
            if showsIndicator {
                PlaybackOffsetIndicator()
                    .scaleEffect(1.4)
                    .allowsHitTesting(false)
            }
        }
        .anchorPreference(key: SystemPlayerMenuAnchors.self, value: .bounds) { [menu: $0] }
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Round glass button of the system style that acts right away, such as the Live TV channel list.
struct SystemPlayerActionButton: View {
    var systemImage: String
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            SystemPlayerButtonLabel(systemImage: systemImage)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    /// Draws the presented menu above the button that opened it, aligned on its trailing edge like the system menus.
    func systemPlayerMenus(
        presentedMenu: Binding<SystemPlayerMenu?>,
        sections: @escaping (SystemPlayerMenu) -> [PlayerMenuSection],
    ) -> some View {
        overlayPreferenceValue(SystemPlayerMenuAnchors.self) { anchors in
            GeometryReader { proxy in
                if let menu = presentedMenu.wrappedValue, let anchor = anchors[menu] {
                    let button = proxy[anchor]
                    SystemPlayerMenuPanel(
                        sections: sections(menu),
                        onClose: { presentedMenu.wrappedValue = nil },
                    )
                    .id(menu)
                    .padding(.trailing, max(proxy.size.width - button.maxX, 0))
                    .frame(
                        width: proxy.size.width,
                        height: max(button.minY - SystemPlayerMenuMetrics.gap, 0),
                        alignment: .bottomTrailing,
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                }
            }
        }
    }
}

private struct SystemPlayerMenuAnchors: PreferenceKey {
    static let defaultValue: [SystemPlayerMenu: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [SystemPlayerMenu: Anchor<CGRect>],
        nextValue: () -> [SystemPlayerMenu: Anchor<CGRect>],
    ) {
        value.merge(nextValue()) { $1 }
    }
}

private enum SystemPlayerMenuMetrics {
    static let gap: CGFloat = 20
    static let width: CGFloat = 520
    static let maxHeight: CGFloat = 620
    static let cornerRadius: CGFloat = 36
    static let rowCornerRadius: CGFloat = 22
    static let edgeFade: CGFloat = 40
}

private struct SystemPlayerButtonLabel: View {
    var systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 28, weight: .semibold))
            .frame(width: 44, height: 44)
    }
}

/// A submenu replaces its parent in place, as in the system menus; Back returns to the parent, then closes.
private struct SystemPlayerMenuPanel: View {
    var sections: [PlayerMenuSection]
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Option ids of the opened submenus, outermost first. Resolved against the current options on every update,
    /// so tracks or values changing while the menu is open show up right away.
    @State private var path: [String] = []
    @FocusState private var focusedOption: String?
    @FocusState private var isPanelFocused: Bool
    @State private var contentHeight: CGFloat = 0
    @State private var isClippedAbove = false
    @State private var isClippedBelow = false

    private var visibleSections: [PlayerMenuSection] {
        var current = sections
        for id in path {
            guard let submenu = current.option(id: id)?.submenuSections else { break }
            current = submenu
        }
        return current
    }

    private var submenuTitle: String? {
        path.last.flatMap { sections.option(id: $0)?.title }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SystemPlayerMenuMetrics.cornerRadius, style: .continuous)
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let submenuTitle {
                    header(submenuTitle)
                }
                ForEach(Array(visibleSections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 {
                        Divider()
                            .overlay(.strokeSubtle)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                    if let title = section.title, submenuTitle == nil {
                        header(title)
                    }
                    ForEach(section.options) { option in
                        row(option)
                    }
                }
            }
            .padding(14)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: [Bool].self) { geometry in
            [
                geometry.contentOffset.y > 1,
                geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1,
            ]
        } action: { _, clipped in
            withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion)) {
                isClippedAbove = clipped[0]
                isClippedBelow = clipped[1]
            }
        }
        // Rows scrolled past an edge fade out instead of being cut in the middle of their text.
        .mask {
            VStack(spacing: 0) {
                edgeFade(towards: .top, isActive: isClippedAbove)
                Color.black
                edgeFade(towards: .bottom, isActive: isClippedBelow)
            }
        }
        .frame(width: SystemPlayerMenuMetrics.width)
        .frame(height: min(contentHeight, SystemPlayerMenuMetrics.maxHeight))
        .background(Color.black.opacity(0.35), in: shape)
        .videoOverlayGlass(in: shape)
        .clipShape(shape)
        // With every row disabled, the panel holds the focus itself so Back still reaches it and closes the menu.
        .focusable(visibleSections.initialFocusOption == nil)
        .focusEffectDisabled()
        .focused($isPanelFocused)
        .focusSection()
        .environment(\.colorScheme, .dark)
        .onAppear(perform: focusInitialOption)
        .onExitCommand {
            if path.isEmpty {
                onClose()
            } else {
                let parent = path.removeLast()
                focus(parent)
            }
        }
    }

    private func edgeFade(towards edge: UnitPoint, isActive: Bool) -> some View {
        ZStack {
            LinearGradient(colors: [.black, .clear], startPoint: edge == .top ? .bottom : .top, endPoint: edge)
            Color.black.opacity(isActive ? 0 : 1)
        }
        .frame(height: SystemPlayerMenuMetrics.edgeFade)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.facts.weight(.medium))
            .foregroundStyle(.textSecondary)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ option: PlayerMenuOption) -> some View {
        let isFocused = focusedOption == option.id
        return Button {
            activate(option)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "checkmark")
                    .font(.facts.weight(.bold))
                    .foregroundStyle(isFocused ? Color.black : .selectionAccent)
                    .opacity(option.isSelected ? 1 : 0)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(.bodyText.weight(.medium))
                        .foregroundStyle(isFocused ? Color.black : .textPrimary)
                    if let subtitle = option.subtitle {
                        Text(subtitle)
                            .font(.cardMetadata)
                            .foregroundStyle(isFocused ? Color.black.opacity(0.6) : .textSecondary)
                    }
                }
                .lineLimit(2)
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if option.submenuSections != nil {
                    Image(systemName: "chevron.right")
                        .font(.facts.weight(.semibold))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.6) : .textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isFocused ? Color.white : .clear,
                in: RoundedRectangle(cornerRadius: SystemPlayerMenuMetrics.rowCornerRadius, style: .continuous),
            )
            .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: isFocused)
        }
        .buttonStyle(SystemPlayerMenuRowStyle())
        .disabled(option.isDisabled)
        .opacity(option.isDisabled ? 0.45 : 1)
        .focused($focusedOption, equals: option.id)
        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
    }

    private func activate(_ option: PlayerMenuOption) {
        switch option.kind {
        case .submenu:
            path.append(option.id)
            focusInitialOption()
        case .toggle:
            option.perform()
        case .choice, .action:
            option.perform()
            onClose()
        }
    }

    private func focusInitialOption() {
        guard let option = visibleSections.initialFocusOption else {
            DispatchQueue.main.async {
                isPanelFocused = true
            }
            return
        }
        focus(option.id)
    }

    private func focus(_ id: String?) {
        DispatchQueue.main.async {
            focusedOption = id
        }
    }
}

/// Draws the focus itself, without the system lift and highlight that would cover the row.
private struct SystemPlayerMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
