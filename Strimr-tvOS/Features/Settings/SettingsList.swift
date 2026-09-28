import SwiftUI

/// Eager, non-recycling rows give every control exactly one place in the focus tree.
/// In particular, no List cell wraps a separately focused Button or Toggle.
struct SettingsList<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        SettingsScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ForEach(sections: content()) { section in
                    VStack(alignment: .leading, spacing: 16) {
                        if !section.header.isEmpty {
                            section.header
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(subviews: section.content) { row in
                                row.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        if !section.footer.isEmpty {
                            section.footer
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .buttonStyle(.bordered)
    }
}

/// Persist geometry rather than keeping hidden scroll/focus containers alive.
struct SettingsScrollView<Content: View>: View {
    @Environment(SettingsNavigation.self) private var navigation
    @Environment(\.settingsFocusContext) private var context
    @State private var position = ScrollPosition(edge: .top)
    @State private var restoredPosition = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
        }
        .scrollPosition($position)
        .onAppear {
            guard !restoredPosition else { return }
            restoredPosition = true
            if let pageID = context?.pageID, let offset = navigation.scrollOffsets[pageID] {
                position.scrollTo(y: offset)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, offset in
            guard restoredPosition, let pageID = context?.pageID else { return }
            navigation.scrollOffsets[pageID] = offset
        }
    }
}
