/// Shared helpers for Reduce Motion, tap target size and large text.
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum Motion {
    static var isReduced: Bool {
#if os(iOS)
        UIAccessibility.isReduceMotionEnabled
#else
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
#endif
    }

    /// `animation`, or no animation at all when Reduce Motion is on. For scrolling and expanding.
    static func animation(_ animation: Animation) -> Animation? {
        isReduced ? nil : animation
    }
}

extension AnyTransition {
    /// Slides and fades, or only fades when Reduce Motion is on.
    static func slideAndFade(_ edge: Edge) -> AnyTransition {
        Motion.isReduced ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

extension View {
    /// Gives a compact text button the 44pt tall tap area Apple's guidelines ask for, without
    /// changing how it looks.
    func comfortableTapTarget() -> some View {
        frame(minHeight: 44).contentShape(Rectangle())
    }
}

/// Shows content as it is, or in a scroll view once large text makes it taller than the screen.
struct ScrollsWhenTooTall<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }
}

/// A row that becomes a leading-aligned column at accessibility text sizes, so that long names and
/// labels get the full width instead of breaking mid-word.
struct AdaptiveStack<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}

/// A `Spacer` for use in an `AdaptiveStack`: nothing once it has become a column.
struct AdaptiveSpacer: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
    }
}

/// Drops a heading's icon at accessibility text sizes, where it squeezes the title mid-word.
struct AdaptiveLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        AdaptiveLabel(configuration: configuration)
    }

    private struct AdaptiveLabel: View {
        let configuration: LabelStyleConfiguration
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            if dynamicTypeSize.isAccessibilitySize {
                configuration.title
            } else {
                Label { configuration.title } icon: { configuration.icon }
            }
        }
    }
}
