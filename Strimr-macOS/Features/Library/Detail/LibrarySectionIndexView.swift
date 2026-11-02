import SwiftUI

struct LibrarySectionIndexView: View {
    static let width: CGFloat = 24

    let sectionIndex: LibrarySectionIndex
    let currentSection: LibrarySectionIndex.Section?
    let onSelect: (LibrarySectionIndex.Section) -> Void

    private let rowHeight: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let slots = max(Int(proxy.size.height / rowHeight), LibrarySectionIndex.minimumSectionCount)
            VStack(spacing: 0) {
                ForEach(Array(sectionIndex.compactEntries(fitting: slots).enumerated()), id: \.offset) { _, entry in
                    if let section = entry.firstSection {
                        LetterButton(
                            title: title(for: entry),
                            isCurrent: isCurrent(entry),
                            height: rowHeight,
                        ) {
                            onSelect(section)
                        }
                    }
                }
            }
            .frame(width: Self.width)
            .frame(maxHeight: .infinity)
        }
        .frame(width: Self.width)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("library.browse.sectionIndex.label"))
    }

    private func title(for entry: LibrarySectionIndex.CompactEntry) -> String {
        switch entry {
        case let .section(section): section.title
        case .collapsed: "•"
        }
    }

    private func isCurrent(_ entry: LibrarySectionIndex.CompactEntry) -> Bool {
        guard let currentSection else { return false }
        return switch entry {
        case let .section(section): section == currentSection
        case let .collapsed(sections): sections.contains(currentSection)
        }
    }
}

private struct LetterButton: View {
    let title: String
    let isCurrent: Bool
    let height: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.cardMetadata.weight(.semibold))
                .foregroundStyle(foreground)
                .frame(width: LibrarySectionIndexView.width, height: height)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered ? Color.surfaceRaised : Color.clear),
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Motion.focus, value: isHovered)
        .accessibilityLabel(Text(verbatim: title))
    }

    private var foreground: Color {
        if isCurrent {
            return .selectionAccent
        }
        return isHovered ? .textPrimary : .textSecondary
    }
}
