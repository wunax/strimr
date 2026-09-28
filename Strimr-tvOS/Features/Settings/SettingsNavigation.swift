import SwiftUI

/// Navigation stays inside the detail column; each category retains its own pages.
@MainActor
@Observable
final class SettingsNavigation {
    struct Page: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let content: AnyView
    }

    var category: SettingsCategory = .playback
    var pages: [SettingsCategory: [Page]] = [:]
    var sidebarFocused = true
    var sidebarRequest = 0
    var detailRequest = 0
    var focusedControls: [String: String] = [:]

    var currentPages: [Page] {
        pages[category, default: []]
    }

    var pageID: String {
        currentPages.last?.id.uuidString ?? category.rawValue
    }

    func push(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) {
        pages[category, default: []].append(Page(title: title, content: AnyView(content())))
        enterDetail()
    }

    func pop() {
        guard !currentPages.isEmpty else { return }
        if let page = pages[category]?.removeLast() {
            focusedControls[page.id.uuidString] = nil
        }
        enterDetail()
    }

    func finishSeerrSetup() {
        guard pages[.integrations, default: []].count > 1 else { return }
        pages[.integrations] = Array(pages[.integrations, default: []].prefix(1))
        if category == .integrations, !sidebarFocused {
            enterDetail()
        }
    }

    func restartSeerrSetup() {
        guard pages[.integrations, default: []].count > 2 else { return }
        pages[.integrations] = Array(pages[.integrations, default: []].prefix(2))
        if category == .integrations, !sidebarFocused {
            enterDetail()
        }
    }

    func enterDetail() {
        sidebarFocused = false
        detailRequest += 1
    }

    func enterSidebar() {
        sidebarFocused = true
        sidebarRequest += 1
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case playback, audio, subtitles, interface, integrations

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .playback: "settings.playback.title"
        case .audio: "settings.playback.audio.title"
        case .subtitles: "settings.playback.subtitles.title"
        case .interface: "settings.interface.title"
        case .integrations: "settings.integrations.title"
        }
    }

    var symbol: String {
        switch self {
        case .playback: "play.rectangle"
        case .audio: "speaker.wave.2"
        case .subtitles: "captions.bubble"
        case .interface: "rectangle.grid.2x2"
        case .integrations: "square.stack.3d.up"
        }
    }
}

struct SettingsFocusContext {
    let pageID: String
    let namespace: Namespace.ID
    let active: Bool
}

extension EnvironmentValues {
    @Entry var settingsFocusContext: SettingsFocusContext?
}

/// Keep inactive pages mounted so their scroll offsets and editing state survive navigation.
struct SettingsDetailPage<Content: View>: View {
    @Environment(SettingsNavigation.self) private var navigation
    @Environment(\.resetFocus) private var resetFocus
    @Namespace private var namespace
    let pageID: String
    let active: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(
                \.settingsFocusContext,
                SettingsFocusContext(pageID: pageID, namespace: namespace, active: active),
            )
            .focusScope(namespace)
            .focusSection()
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .disabled(!active)
            .accessibilityHidden(!active)
            .onAppear {
                if active, !navigation.sidebarFocused {
                    resetFocus(in: namespace)
                }
            }
            .onChange(of: active) { _, active in
                if active, !navigation.sidebarFocused {
                    resetFocus(in: namespace)
                }
            }
            .onChange(of: navigation.detailRequest) { _, _ in
                if active {
                    resetFocus(in: namespace)
                }
            }
    }
}

private struct SettingsControlFocus: ViewModifier {
    @Environment(SettingsNavigation.self) private var navigation
    @Environment(\.settingsFocusContext) private var context
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focused: Bool
    let id: String
    let isDefault: Bool
    let exitsLeft: Bool

    func body(content: Content) -> some View {
        if let context {
            content
                .focused($focused)
                .prefersDefaultFocus(
                    navigation.focusedControls[context.pageID].map { $0 == id } ?? isDefault,
                    in: context.namespace,
                )
                .onAppear {
                    restoreFocus(context)
                }
                .onChange(of: navigation.detailRequest) { _, _ in
                    restoreFocus(context)
                }
                .onChange(of: context.active) { _, active in
                    if active {
                        restoreFocus(context)
                    }
                }
                .onChange(of: isEnabled) { _, enabled in
                    if !enabled, context.active, navigation.focusedControls[context.pageID] == id {
                        navigation.focusedControls[context.pageID] = nil
                    }
                }
                .onChange(of: focused) { _, value in
                    if value {
                        navigation.focusedControls[context.pageID] = id
                        navigation.sidebarFocused = false
                    }
                }
                .onMoveCommand { direction in
                    if direction == .left, exitsLeft {
                        navigation.enterSidebar()
                    }
                }
        } else {
            content
        }
    }

    private func restoreFocus(_ context: SettingsFocusContext) {
        guard context.active, isEnabled, !navigation.sidebarFocused else { return }
        if navigation.focusedControls[context.pageID].map({ $0 == id }) ?? isDefault {
            focused = true
        }
    }
}

extension View {
    func settingsFocus(_ id: String, isDefault: Bool = false, exitsLeft: Bool = true) -> some View {
        modifier(SettingsControlFocus(id: id, isDefault: isDefault, exitsLeft: exitsLeft))
    }
}

struct SettingsLink<Label: View, Destination: View>: View {
    @Environment(SettingsNavigation.self) private var navigation
    let title: LocalizedStringKey
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            navigation.push(title, content: destination)
        } label: {
            label()
        }
    }
}

extension SettingsLink where Label == Text {
    init(_ title: LocalizedStringKey, @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.destination = destination
        label = { Text(title) }
    }
}

struct SettingsPicker<Value: Hashable>: View {
    @Environment(SettingsNavigation.self) private var navigation
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [Value]
    let optionTitle: (Value) -> Text

    init(
        _ title: LocalizedStringKey,
        selection: Binding<Value>,
        options: [Value],
        optionTitle: @escaping (Value) -> Text,
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.optionTitle = optionTitle
    }

    var body: some View {
        Button {
            navigation.push(title) {
                SettingsOptionsView(selection: $selection, options: options, optionTitle: optionTitle)
            }
        } label: {
            HStack(spacing: 20) {
                Text(title)
                Spacer(minLength: 16)
                optionTitle(selection)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsOptionsView<Value: Hashable>: View {
    @Environment(SettingsNavigation.self) private var navigation
    @Binding var selection: Value
    let options: [Value]
    let optionTitle: (Value) -> Text

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(options.enumerated()), id: \.element) { index, value in
                    Button {
                        selection = value
                        navigation.pop()
                    } label: {
                        HStack {
                            optionTitle(value)
                            Spacer()
                            if selection == value {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.brandPrimary)
                            }
                        }
                    }
                    .id(value)
                    .settingsFocus("option-\(index)", isDefault: selection == value)
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
                }
            }
            .listStyle(.plain)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
    }
}
