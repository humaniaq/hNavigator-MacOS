import SwiftUI

// MARK: - Visual Effect (blur) for glassmorphism
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - RetroBox: The universal panel container
public struct RetroBox<Content: View>: View {
    public let title: String?
    public let theme: AppTheme
    public let isActive: Bool
    public let doubleLine: Bool
    public let onDoubleTapTitle: (() -> Void)?
    public let content: Content

    public init(
        title: String? = nil,
        theme: AppTheme,
        isActive: Bool = false,
        doubleLine: Bool = true,
        onDoubleTapTitle: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.theme = theme
        self.isActive = isActive
        self.doubleLine = doubleLine
        self.onDoubleTapTitle = onDoubleTapTitle
        self.content = content()
    }

    private var borderLineColor: Color {
        isActive ? theme.activeBorderColor : theme.borderColor
    }

    public var body: some View {
        ZStack {
            // ── Background ──────────────────────────────────────────────
            backgroundLayer

            // ── Content ─────────────────────────────────────────────────
            content
                .padding(doubleLine ? 10 : 6)

            // ── Border overlay ───────────────────────────────────────────
            borderLayer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Active glow shadow
        .shadow(
            color: isActive ? theme.glowColor.opacity(0.35) : theme.shadowColor.opacity(0.25),
            radius: isActive ? 12 : 5,
            x: 0, y: 3
        )
    }

    // MARK: Backgrounds
    @ViewBuilder
    private var backgroundLayer: some View {
        switch theme {
        case .glassPro:
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(theme.panelBgColor)
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .cornerRadius(theme.cornerRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: isActive
                                    ? [theme.glowColor.opacity(0.8), theme.glowColor.opacity(0.2)]
                                    : [Color.white.opacity(0.25), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isActive ? 1.5 : 1.0
                        )
                )

        case .arctic:
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(theme.panelBgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .strokeBorder(borderLineColor, lineWidth: isActive ? 1.5 : 1.0)
                )

        case .classicBlue, .neonNoir, .retroDark, .humaniaq:
            // Retro flat with subtle gradient top-to-bottom
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.panelBgColor.opacity(1.0),
                            theme.panelBgColor.opacity(0.88)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    // MARK: Borders + title
    @ViewBuilder
    private var borderLayer: some View {
        GeometryReader { geo in
            ZStack {
                if theme == .glassPro || theme == .arctic || theme == .humaniaq {
                    // Already handled in backgroundLayer
                    EmptyView()
                } else if doubleLine {
                    // Outer border
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .strokeBorder(borderLineColor, lineWidth: 1.0)

                    // Inner border inset
                    RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 2))
                        .strokeBorder(borderLineColor.opacity(0.45), lineWidth: 0.75)
                        .padding(3)
                } else {
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .strokeBorder(borderLineColor, lineWidth: 1.5)
                }

                // ── Title badge ─────────────────────────────────────
                if let title = title, !title.isEmpty {
                    titleBadge(title: title, geo: geo)
                }
            }
        }
    }

    @ViewBuilder
    private func titleBadge(title: String, geo: GeometryProxy) -> some View {
        if isActive {
            // Active: gradient pill
            Text(" \(title) ")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(theme.accentGradient)
                        .shadow(color: theme.glowColor.opacity(0.5), radius: 6)
                )
                .onTapGesture(count: 2) {
                    onDoubleTapTitle?()
                }
                .position(x: geo.size.width / 2, y: 0)
        } else {
            Text(" \(title) ")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(theme.subtleTextColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                .background(theme.panelBgColor)
                .overlay(
                    Capsule().strokeBorder(theme.borderColor, lineWidth: 0.75)
                )
                .clipShape(Capsule())
                .onTapGesture(count: 2) {
                    onDoubleTapTitle?()
                }
                .position(x: geo.size.width / 2, y: 0)
        }
    }
}
