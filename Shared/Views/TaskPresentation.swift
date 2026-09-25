import SwiftUI

/// Task presentations use the system presentation lifecycle for dismissal, keyboard
/// handling and restoration of the presenting focus. Other platforms retain sheets.
enum TaskPresentationStyle {
    case modal
    case contextual
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
                    .presentationBackground(.clear)
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
                    .presentationBackground(.clear)
            }
        #else
            sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }
}

#if os(tvOS)
    struct TVModalView<Content: View>: View {
        @ViewBuilder var content: () -> Content

        var body: some View {
            ZStack {
                Color.black.opacity(0.8).ignoresSafeArea()
                content()
                    .padding(32)
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
            Group {
                switch style {
                case .modal:
                    TVModalView(content: content)
                case .contextual:
                    TVContextPanelView(content: content)
                }
            }
            .onExitCommand { dismiss() }
        }
    }
#endif
