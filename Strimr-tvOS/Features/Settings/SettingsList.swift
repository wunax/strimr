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
    @State private var requestedOffset: CGFloat?
    @State private var restoredPosition = false
    @State private var geometry: SettingsScrollGeometry?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
        }
        .scrollPosition($position)
        .preference(
            key: SettingsScrollReadyKey.self,
            value: restoredPosition ? Set([context?.pageID].compactMap(\.self)) : [],
        )
        .onAppear {
            guard requestedOffset == nil, let pageID = context?.pageID else { return }
            let offset = navigation.scrollOffsets[pageID] ?? 0
            requestedOffset = offset
            position.scrollTo(y: offset)
            if let geometry {
                recordGeometry(geometry)
            }
        }
        .onScrollGeometryChange(for: SettingsScrollGeometry.self) { geometry in
            SettingsScrollGeometry(
                offset: max(0, geometry.contentOffset.y + geometry.contentInsets.top),
                maximumOffset: max(
                    0,
                    geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                        - geometry.containerSize.height,
                ),
            )
        } action: { _, geometry in
            self.geometry = geometry
            recordGeometry(geometry)
        }
    }

    private func recordGeometry(_ geometry: SettingsScrollGeometry) {
        guard let pageID = context?.pageID, pageID == navigation.pageID,
              let requestedOffset else { return }
        if !restoredPosition {
            let destination = min(requestedOffset, geometry.maximumOffset)
            guard abs(geometry.offset - destination) < 1 else { return }
            restoredPosition = true
        }
        // Ignore teardown geometry and the initial zero offset while restoring an old page.
        navigation.scrollOffsets[pageID] = geometry.offset
    }
}

private struct SettingsScrollGeometry: Equatable {
    let offset: CGFloat
    let maximumOffset: CGFloat
}
