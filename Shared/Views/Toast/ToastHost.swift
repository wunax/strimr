import SwiftUI

extension View {
    /// Installs the window's `ToastCenter`. Install it once, at the root of each window.
    func toastHost() -> some View {
        modifier(ToastHost())
    }
}

private struct ToastHost: ViewModifier {
    @State private var center = ToastCenter()

    func body(content: Content) -> some View {
        content
            .environment(center)
        #if os(macOS)
            .overlay(alignment: .topTrailing) {
                ToastOverlay(center: center)
            }
        #else
            .background(ToastLayer(center: center, toastID: center.current?.id))
        #endif
    }
}

#if !os(macOS)
    /// Draws the toasts straight in the window, above the root view and any sheet presented over it, which a SwiftUI
    /// overlay would sit under. A separate window would take over the status bar and orientation of the app.
    private struct ToastLayer: UIViewRepresentable {
        let center: ToastCenter
        let toastID: Toast.ID?

        func makeUIView(context _: Context) -> AnchorView {
            AnchorView(center: center)
        }

        func updateUIView(_ view: AnchorView, context _: Context) {
            if toastID != nil {
                view.bringLayerToFront()
            }
        }

        final class AnchorView: UIView {
            private let host: UIHostingController<ToastOverlay>

            init(center: ToastCenter) {
                host = UIHostingController(rootView: ToastOverlay(center: center))
                super.init(frame: .zero)
                host.view.backgroundColor = .clear
                host.view.isUserInteractionEnabled = false
                host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                guard let window else {
                    host.view.removeFromSuperview()
                    return
                }
                host.view.frame = window.bounds
                window.addSubview(host.view)
            }

            /// Sheets presented after the layer was installed are added above it.
            func bringLayerToFront() {
                host.view.superview?.bringSubviewToFront(host.view)
            }
        }
    }
#endif

private struct ToastOverlay: View {
    let center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: alignment) {
            Color.clear
            if let toast = center.current {
                ToastView(toast: toast)
                    .padding(padding)
                    .id(toast.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.animation(Motion.panel, reduceMotion: reduceMotion), value: center.current?.id)
        .allowsHitTesting(false)
        .environment(\.colorScheme, .dark)
    }

    private var alignment: Alignment {
        #if os(iOS)
            .top
        #else
            .topTrailing
        #endif
    }

    private var padding: EdgeInsets {
        #if os(tvOS)
            EdgeInsets()
        #elseif os(macOS)
            EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        #else
            EdgeInsets(top: 8, leading: LayoutMetrics.pageMargin, bottom: 0, trailing: LayoutMetrics.pageMargin)
        #endif
    }
}

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        WidthLimit(maxWidth: maxWidth) {
            content
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .overlayPanelSurface(in: RoundedRectangle(
                    cornerRadius: LayoutMetrics.overlayCornerRadius,
                    style: .continuous,
                ))
        }
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .foregroundStyle(.textPrimary)
                if let message = toast.message {
                    Text(message)
                        .font(.facts)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(3)
                }
            }
        }
        .font(.rowTitle)
    }

    private var systemImage: String {
        switch toast.style {
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch toast.style {
        case .success: .green
        case .failure: .yellow
        }
    }

    private var maxWidth: CGFloat {
        #if os(tvOS)
            640
        #else
            420
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            32
        #else
            18
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(tvOS)
            22
        #else
            12
        #endif
    }
}

/// Proposes at most `maxWidth` and takes the size of its content, so a short toast hugs its text where a
/// `frame(maxWidth:)` would stretch it.
private struct WidthLimit: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = min(proposal.width ?? maxWidth, maxWidth)
        return subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
