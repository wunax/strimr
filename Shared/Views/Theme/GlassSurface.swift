import SwiftUI

extension View {
    /// Liquid Glass where available, a thin material otherwise.
    func glassSurface(
        in shape: some Shape = Capsule(style: .continuous),
        tint: Color? = nil,
        interactive: Bool = false,
    ) -> some View {
        modifier(GlassSurfaceModifier(shape: shape, tint: tint, interactive: interactive))
    }

    /// Glass for surfaces drawn over playing video. Re-blurring the video every frame is too costly on older
    /// hardware, so those devices get a near-opaque fill instead.
    func videoOverlayGlass(in shape: some Shape = Capsule(style: .continuous)) -> some View {
        modifier(VideoOverlayGlassModifier(shape: shape))
    }

    /// Surface of modals and panels floating over a page: glass over a dark base, so dense text stays legible over
    /// bright artwork.
    func overlayPanelSurface(in shape: some Shape) -> some View {
        background(Color.black.opacity(0.5), in: shape)
            .glassSurface(in: shape)
            .shadow(color: .black.opacity(0.35), radius: 30, y: 8)
    }

    /// Keeps text drawn straight on playing video, without a surface behind it, readable over bright frames.
    func videoTextShadow() -> some View {
        shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

private struct GlassSurfaceModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.black.opacity(0.88), in: shape)
        } else if #available(iOS 26.0, tvOS 26.0, macOS 26.0, *) {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

private struct VideoOverlayGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: S

    func body(content: Content) -> some View {
        if reduceTransparency || DeviceCapabilities.prefersOpaqueVideoOverlays {
            content.background(Color.black.opacity(0.88), in: shape)
        } else {
            content.glassSurface(in: shape)
        }
    }
}

enum DeviceCapabilities {
    /// Apple TV HD (AppleTV5,x) and the first Apple TV 4K (AppleTV6,x) drop frames when glass samples video.
    static let prefersOpaqueVideoOverlays: Bool = {
        #if os(tvOS)
            var systemInfo = utsname()
            uname(&systemInfo)
            let machine = withUnsafeBytes(of: &systemInfo.machine) { buffer in
                String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
            }
            return machine.hasPrefix("AppleTV5,") || machine.hasPrefix("AppleTV6,")
        #else
            return false
        #endif
    }()
}
