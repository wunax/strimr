import SwiftUI

/// Task presentations use the system presentation lifecycle for dismissal, keyboard
/// handling and restoration of the presenting focus. Other platforms retain sheets.
enum TaskPresentationStyle {
    case modal
    /// A narrower modal, for short forms and lists.
    case compactModal
    case contextual
    /// Opaque and edge to edge, for flows that need full attention and keep their own navigation stack.
    case fullScreen
}

extension View {
    @ViewBuilder
    func taskPresentation<Item: Identifiable>(
        item: Binding<Item?>,
        style: TaskPresentationStyle = .modal,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> some View,
    ) -> some View {
        #if os(tvOS)
            fullScreenCover(item: item, onDismiss: onDismiss) { value in
                TVTaskPresentationView(style: style) { content(value) }
            }
        #else
            sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }

    @ViewBuilder
    func taskPresentation(
        isPresented: Binding<Bool>,
        style: TaskPresentationStyle = .modal,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> some View,
    ) -> some View {
        #if os(tvOS)
            fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
                TVTaskPresentationView(style: style, content: content)
            }
        #else
            sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }
}

#if os(tvOS)
    struct TVModalView<Content: View>: View {
        var maxWidth: CGFloat = 1560
        @ViewBuilder var content: () -> Content

        var body: some View {
            ZStack {
                Color.black.opacity(0.8).ignoresSafeArea()
                content()
                    // Focused rows and fields grow past their scroll view's bounds.
                    .scrollClipDisabled()
                    .frame(maxWidth: maxWidth, maxHeight: .infinity)
                    .padding(40)
                    .background(Color("Background"), in: RoundedRectangle(cornerRadius: 28))
                    .padding(48)
            }
            .focusSection()
        }
    }

    /// An opaque reading surface covering only the trailing portion of the screen.
    /// Also used directly by the player, without presenting/remounting the video.
    struct TVContextPanelView<Content: View>: View {
        @ViewBuilder var content: () -> Content

        var body: some View {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    content()
                        .padding(32)
                        .frame(width: min(720, geometry.size.width * 0.44))
                        .frame(maxHeight: .infinity)
                        .background(Color("Background").opacity(0.98))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1)
                        }
                        .shadow(color: .black.opacity(0.5), radius: 30, x: -12)
                }
            }
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
            .focusSection()
        }
    }

    private struct TVTaskPresentationView<Content: View>: View {
        @Environment(\.dismiss) private var dismiss
        let style: TaskPresentationStyle
        @ViewBuilder var content: () -> Content

        var body: some View {
            // A presentation over this one (dialog, alert) makes it fall back to the system appearance.
            presentation
                .environment(\.colorScheme, .dark)
        }

        @ViewBuilder
        private var presentation: some View {
            switch style {
            case .modal:
                TVModalView(content: content)
                    .presentationBackground(.clear)
                    .onExitCommand { dismiss() }
            case .compactModal:
                TVModalView(maxWidth: 1000, content: content)
                    .presentationBackground(.clear)
                    .onExitCommand { dismiss() }
            case .contextual:
                TVContextPanelView(content: content)
                    .presentationBackground(.clear)
                    .onExitCommand { dismiss() }
            case .fullScreen:
                // No exit handler: Menu must pop the content's navigation stack before dismissing.
                content()
                    .background(Color("Background").ignoresSafeArea())
            }
        }
    }
#endif

/// tvOS modals have their own header; a nested navigation bar can float over
/// scrolling content inside an inset full-screen presentation.
struct TaskModalNavigationView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(tvOS)
            content()
        #else
            NavigationStack { content() }
        #endif
    }
}

extension View {
    func taskModalTitle(_ title: LocalizedStringKey) -> some View {
        taskModalTitle(Text(title))
    }

    func taskModalTitle(verbatim title: String) -> some View {
        taskModalTitle(Text(verbatim: title))
    }

    @ViewBuilder
    private func taskModalTitle(_ title: Text) -> some View {
        #if os(tvOS)
            VStack(alignment: .leading, spacing: 24) {
                title
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                Divider()
                self
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        #else
            navigationTitle(title)
        #endif
    }

    @ViewBuilder
    func taskModalActions(grouped: Bool = false, @ViewBuilder actions: () -> some View) -> some View {
        #if os(tvOS)
            VStack(spacing: 20) {
                self
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 24) { actions() }
                        .padding(12)
                }
                .fixedSize(horizontal: false, vertical: true)
                .focusSection()
            }
        #else
            if grouped {
                toolbar { ToolbarItemGroup { actions() } }
            } else {
                toolbar { actions() }
            }
        #endif
    }
}

#if os(tvOS)
    /// Focus treatment for information cards that must be reachable for scrolling.
    struct TVModalReadingFocus: ViewModifier {
        @FocusState private var isFocused: Bool

        func body(content: Content) -> some View {
            content
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFocused ? Color.white.opacity(0.8) : .clear, lineWidth: 2)
                }
                .focusable()
                .focused($isFocused)
        }
    }
#endif
