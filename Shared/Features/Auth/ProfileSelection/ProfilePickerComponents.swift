import SwiftUI

enum ProfilePickerMetrics {
    #if os(tvOS)
        static let avatarSize: CGFloat = 220
        static let entranceAvatarSize: CGFloat = 280
        static let itemSpacing: CGFloat = 64
        static let dotSize: CGFloat = 26
        static let keySize: CGFloat = 96
    #elseif os(macOS)
        static let avatarSize: CGFloat = 132
        static let entranceAvatarSize: CGFloat = 168
        static let itemSpacing: CGFloat = 40
        static let dotSize: CGFloat = 16
    #else
        static let avatarSize: CGFloat = 112
        static let entranceAvatarSize: CGFloat = 148
        static let itemSpacing: CGFloat = 28
        static let dotSize: CGFloat = 16
        static let keySize: CGFloat = 76
    #endif

    static let entranceAnimation = Animation.spring(duration: 0.5, bounce: 0.2)
}

/// Dark backdrop washed with the highlighted profile's tint.
struct ProfilePickerBackground: View {
    /// Nil until profiles are known: the wash then fades in instead of switching from a placeholder color.
    let tint: Color?

    var body: some View {
        ZStack {
            Color.black
            // One layer per palette color, crossfaded by opacity alone: an animation on the whole backdrop
            // also caught the navigation stack's first sizing pass, and the wash grew from the center.
            ForEach(ProfileTint.palette.indices, id: \.self) { index in
                let color = ProfileTint.palette[index]
                wash(color)
                    .animation(.easeInOut(duration: 0.7)) { $0.opacity(color == tint ? 1 : 0) }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private func wash(_ color: Color) -> some View {
        ZStack {
            EllipticalGradient(
                colors: [color.opacity(0.6), color.opacity(0.18), .clear],
                center: .top,
                endRadiusFraction: 1.1,
            )
            EllipticalGradient(
                colors: [color.opacity(0.22), .clear],
                center: .bottomLeading,
                endRadiusFraction: 0.8,
            )
        }
    }
}

/// Round profile avatar: a ring marks the active profile, a glass badge a PIN-protected one.
struct ProfileAvatarView: View {
    let choice: ProfileChoice
    var size: CGFloat = ProfilePickerMetrics.avatarSize
    var isHighlighted = false
    var isSwitching = false
    var showsBadges = true
    /// Shared with the other stages so the avatar flies between them.
    var namespace: Namespace.ID?

    private var ringWidth: CGFloat {
        max(3, size * 0.025)
    }

    var body: some View {
        image
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(Circle())
            .overlay {
                if isSwitching {
                    Circle().fill(.badgeBackground)
                    ProgressView().tint(.textPrimary)
                }
            }
            .matchedAvatar(choice.id, in: namespace)
            .frame(width: size, height: size)
            .padding(ringWidth * 2)
            .overlay {
                if showsBadges, choice.isActive {
                    Circle().strokeBorder(choice.tint, lineWidth: ringWidth)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsBadges, choice.requiresPIN {
                    lockBadge
                }
            }
            .animation(.spring(duration: 0.35)) { content in
                content
                    .shadow(color: choice.tint.opacity(isHighlighted ? 0.7 : 0), radius: size * 0.16)
                    .scaleEffect(isHighlighted ? 1.1 : 1)
            }
    }

    @ViewBuilder
    private var image: some View {
        if choice.isLocal {
            ProfileInitialsAvatar(initials: choice.initials, tint: choice.tint)
        } else {
            CachedProfileAvatar(profileID: choice.avatarProfileID, url: choice.avatarURL) {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [choice.tint, choice.tint.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
        .overlay {
            Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.textPrimary)
                .padding(size * 0.26)
        }
    }

    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: size * 0.11, weight: .semibold))
            .foregroundStyle(.textPrimary)
            .frame(width: size * 0.26, height: size * 0.26)
            .glassSurface(in: Circle())
    }
}

struct ProfileNameLabel: View {
    let choice: ProfileChoice
    var isHighlighted = false

    var body: some View {
        Text(choice.name)
            .font(.rowTitle)
            .foregroundStyle(isHighlighted ? .textPrimary : .textSecondary)
            .lineLimit(1)
            .frame(maxWidth: ProfilePickerMetrics.avatarSize * 1.2)
    }
}

struct PINDotsView: View {
    let count: Int
    var length = 4

    var body: some View {
        let size = ProfilePickerMetrics.dotSize
        HStack(spacing: size) {
            ForEach(0 ..< length, id: \.self) { index in
                Circle()
                    .fill(index < count ? Color.textPrimary : Color.strokeSubtle)
                    .frame(width: size, height: size)
                    .scaleEffect(index < count ? 1 : 0.75)
            }
        }
        .animation(.spring(duration: 0.2), value: count)
    }
}

/// Horizontal shake; animate `trigger` by one to shake once.
struct ShakeEffect: GeometryEffect {
    var trigger: CGFloat

    var animatableData: CGFloat {
        get { trigger }
        set { trigger = newValue }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 12 * sin(trigger * .pi * 4), y: 0))
    }
}

extension View {
    func shake(_ count: Int) -> some View {
        modifier(ShakeEffect(trigger: CGFloat(count)))
            .animation(.linear(duration: 0.4), value: count)
    }
}

/// Rows of fixed-size items, each row centered.
struct CenteredFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var x = bounds.midX - row.width / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size),
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if width > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = width
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

/// The chosen profile, centered on its tint: ends the picker and covers the session's first connection.
struct ProfileEntranceView: View {
    let choice: ProfileChoice
    var namespace: Namespace.ID?

    var body: some View {
        VStack(spacing: 28) {
            ProfileAvatarView(
                choice: choice,
                size: ProfilePickerMetrics.entranceAvatarSize,
                showsBadges: false,
                namespace: namespace,
            )
            Text(choice.name)
                .font(.tileTitle)
                .foregroundStyle(.textPrimary)
            ProgressView()
                .tint(.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown while a chosen profile connects, in continuity with the picker's entrance.
struct ProfileActivationView: View {
    let profile: StrimrProfile

    var body: some View {
        let choice = ProfileChoice(profile: profile, isActive: false)
        ZStack {
            ProfilePickerBackground(tint: choice.tint)
            ProfileEntranceView(choice: choice)
        }
        .environment(\.colorScheme, .dark)
    }
}

extension View {
    @ViewBuilder
    func matchedAvatar(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

#if !os(macOS)
    /// Digit keypad drawn in the picker, so the PIN is typed without leaving the scene.
    struct ProfileKeypad: View {
        let canDelete: Bool
        let onDigit: (String) -> Void
        let onDelete: () -> Void

        #if os(tvOS)
            @FocusState private var focusedKey: String?
        #endif

        private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "delete"]]

        var body: some View {
            let spacing = ProfilePickerMetrics.keySize * 0.3
            // A grid keeps the last row aligned: tvOS buttons are larger than their label, the empty key is not.
            Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                ForEach(rows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { key in
                            keyView(key)
                        }
                    }
                }
            }
            #if os(tvOS)
            .onAppear { focusedKey = "1" }
            #endif
        }

        @ViewBuilder
        private func keyView(_ key: String) -> some View {
            switch key {
            case "":
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            case "delete":
                keyButton(key, action: onDelete) {
                    Image(systemName: "delete.left")
                }
                .disabled(!canDelete)
            default:
                keyButton(key, action: { onDigit(key) }) {
                    Text(key)
                }
            }
        }

        private func keyButton(
            _ key: String,
            action: @escaping () -> Void,
            @ViewBuilder label: () -> some View,
        ) -> some View {
            Button(action: action) {
                label()
                    .font(.system(size: ProfilePickerMetrics.keySize * 0.36, weight: .medium, design: .rounded))
                    .frame(width: ProfilePickerMetrics.keySize, height: ProfilePickerMetrics.keySize)
            }
            #if os(tvOS)
            .buttonBorderShape(.circle)
            .focused($focusedKey, equals: key)
            #else
            .buttonStyle(KeypadButtonStyle())
            #endif
        }
    }

    #if os(iOS)
        private struct KeypadButtonStyle: ButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .foregroundStyle(.textPrimary)
                    .contentShape(Circle())
                    .glassSurface(in: Circle())
                    .scaleEffect(configuration.isPressed ? 0.92 : 1)
                    .animation(.spring(duration: 0.2), value: configuration.isPressed)
            }
        }
    #endif
#endif

extension AnyTransition {
    /// Carries its own animation, so switching the session screen does not animate the layout of the others.
    static let profileActivation = AnyTransition.opacity.animation(.easeInOut(duration: 0.4))
}
