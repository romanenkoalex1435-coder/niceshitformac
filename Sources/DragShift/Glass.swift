import AppKit
import SwiftUI

extension View {
    /// Real Liquid Glass on macOS 26 (when built with the macOS 26 SDK), a hand-made glass look elsewhere.
    @ViewBuilder
    func liquidGlass<S: Shape>(_ shape: S, tint: Color?, fallback: AnyShapeStyle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            self.background(FallbackGlass(shape: shape, fill: fallback))
        }
        #else
        self.background(FallbackGlass(shape: shape, fill: fallback))
        #endif
    }
}

/// Lets neighbouring glass shapes refract each other on macOS 26; a plain container elsewhere.
struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 2) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

struct FallbackGlass<S: Shape>: View {
    let shape: S
    let fill: AnyShapeStyle

    var body: some View {
        ZStack {
            shape.fill(fill)
            // Top sheen and a bright rim, the two cues that read as "glass".
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0)], startPoint: .top, endPoint: .center))
            shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.95), Color.white.opacity(0.15), Color.white.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
        }
    }
}

/// Blurs whatever is behind the window (desktop, other apps), clipped to a rounded shape.
struct BehindWindowBlur: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .popover
        view.appearance = NSAppearance(named: .aqua)
        view.maskImage = Self.mask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.maskImage = Self.mask(radius: cornerRadius)
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
