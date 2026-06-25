import SwiftUI
import Combine

public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case classicBlue    = "Classic Blue"
    case neonNoir       = "Neon Noir"
    case glassPro       = "Glass Pro"
    case arctic         = "Arctic"
    case retroDark      = "Retro Dark"
    case humaniaq       = "Humaniaq"

    public var id: String { rawValue }

    // MARK: - Background
    public var backgroundColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 0.0,  green: 0.02, blue: 0.45)
        case .neonNoir:     return Color(red: 0.04, green: 0.0,  blue: 0.08)
        case .glassPro:     return Color(red: 0.07, green: 0.07, blue: 0.14)
        case .arctic:       return Color(red: 0.94, green: 0.96, blue: 0.99)
        case .retroDark:    return Color(red: 0.08, green: 0.08, blue: 0.10)
        case .humaniaq:     return Color(red: 0.9608, green: 0.9451, blue: 0.9098) // Warm paper #F5F1E8
        }
    }

    public var panelBgColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 0.0,  green: 0.02, blue: 0.50)
        case .neonNoir:     return Color(red: 0.06, green: 0.0,  blue: 0.12).opacity(0.95)
        case .glassPro:     return Color.white.opacity(0.06)
        case .arctic:       return Color.white.opacity(0.82)
        case .retroDark:    return Color(red: 0.11, green: 0.11, blue: 0.14)
        case .humaniaq:     return Color(red: 0.9804, green: 0.9725, blue: 0.9529) // Very light warm paper #FAF8F3
        }
    }

    // MARK: - Accent gradient (used for selection highlight, active borders)
    public var accentGradient: LinearGradient {
        switch self {
        case .classicBlue:
            return LinearGradient(colors: [Color(red:0.0, green:0.6, blue:1.0), Color(red:0.0, green:0.4, blue:0.8)], startPoint: .leading, endPoint: .trailing)
        case .neonNoir:
            return LinearGradient(colors: [Color(red:1.0, green:0.0, blue:0.55), Color(red:0.6, green:0.0, blue:1.0)], startPoint: .leading, endPoint: .trailing)
        case .glassPro:
            return LinearGradient(colors: [Color(red:0.4, green:0.2, blue:1.0), Color(red:0.1, green:0.6, blue:1.0)], startPoint: .leading, endPoint: .trailing)
        case .arctic:
            return LinearGradient(colors: [Color(red:0.15, green:0.55, blue:1.0), Color(red:0.3, green:0.75, blue:1.0)], startPoint: .leading, endPoint: .trailing)
        case .retroDark:
            return LinearGradient(colors: [Color(red:0.9, green:0.6, blue:0.0), Color(red:1.0, green:0.4, blue:0.0)], startPoint: .leading, endPoint: .trailing)
        case .humaniaq:
            return LinearGradient(colors: [Color(red: 0.7608, green: 0.4196, blue: 0.2902), Color(red: 0.8196, green: 0.5451, blue: 0.4196)], startPoint: .leading, endPoint: .trailing) // Terracotta gradient #C26B4A
        }
    }

    // MARK: - Glow / neon accent color (single)
    public var glowColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 0.0,  green: 0.7,  blue: 1.0)
        case .neonNoir:     return Color(red: 1.0,  green: 0.05, blue: 0.6)
        case .glassPro:     return Color(red: 0.45, green: 0.25, blue: 1.0)
        case .arctic:       return Color(red: 0.15, green: 0.55, blue: 1.0)
        case .retroDark:    return Color(red: 1.0,  green: 0.55, blue: 0.0)
        case .humaniaq:     return Color(red: 0.7608, green: 0.4196, blue: 0.2902) // Terracotta #C26B4A
        }
    }

    // MARK: - Text
    public var textColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 0.88, green: 0.93, blue: 1.0)
        case .neonNoir:     return Color(red: 0.85, green: 0.9,  blue: 0.95)
        case .glassPro:     return .white
        case .arctic:       return Color(red: 0.12, green: 0.14, blue: 0.20)
        case .retroDark:    return Color(red: 0.9,  green: 0.88, blue: 0.82)
        case .humaniaq:     return Color(red: 0.1686, green: 0.1686, blue: 0.1568) // Ink charcoal #2B2B28
        }
    }

    public var subtleTextColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 0.55, green: 0.68, blue: 0.88)
        case .neonNoir:     return Color(red: 0.5,  green: 0.45, blue: 0.65)
        case .glassPro:     return Color.white.opacity(0.45)
        case .arctic:       return Color(red: 0.45, green: 0.52, blue: 0.65)
        case .retroDark:    return Color(red: 0.5,  green: 0.48, blue: 0.42)
        case .humaniaq:     return Color(red: 0.7333, green: 0.7020, blue: 0.6510) // Warm stone #BBB3A6
        }
    }

    public var folderColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 1.0,  green: 0.85, blue: 0.3)
        case .neonNoir:     return Color(red: 0.0,  green: 0.9,  blue: 1.0)
        case .glassPro:     return Color(red: 0.55, green: 0.85, blue: 1.0)
        case .arctic:       return Color(red: 0.15, green: 0.55, blue: 1.0)
        case .retroDark:    return Color(red: 1.0,  green: 0.75, blue: 0.2)
        case .humaniaq:     return Color(red: 0.5412, green: 0.6039, blue: 0.4824) // Sage #8A9A7B
        }
    }

    public var fileColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 0.88, green: 0.93, blue: 1.0)
        case .neonNoir:     return Color(red: 0.22, green: 1.0,  blue: 0.6)
        case .glassPro:     return Color.white.opacity(0.85)
        case .arctic:       return Color(red: 0.2,  green: 0.3,  blue: 0.5)
        case .retroDark:    return Color(red: 0.75, green: 0.95, blue: 0.65)
        case .humaniaq:     return Color(red: 0.4824, green: 0.4627, blue: 0.4314) // Slightly darker stone
        }
    }

    // MARK: - Selection
    public var selectionBgColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 0.0,  green: 0.5,  blue: 0.9).opacity(0.6)
        case .neonNoir:     return Color(red: 1.0,  green: 0.05, blue: 0.6).opacity(0.35)
        case .glassPro:     return Color.white.opacity(0.15)
        case .arctic:       return Color(red: 0.15, green: 0.55, blue: 1.0).opacity(0.18)
        case .retroDark:    return Color(red: 1.0,  green: 0.55, blue: 0.0).opacity(0.25)
        case .humaniaq:     return Color(red: 0.7608, green: 0.4196, blue: 0.2902).opacity(0.12) // Soft terracotta highlight
        }
    }

    public var selectionTextColor: Color {
        switch self {
        case .classicBlue, .neonNoir, .glassPro, .retroDark: return .white
        case .arctic: return Color(red: 0.08, green: 0.08, blue: 0.12)
        case .humaniaq: return Color(red: 0.1686, green: 0.1686, blue: 0.1568) // Dark ink text for light backgrounds
        }
    }

    // MARK: - Borders
    public var borderColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 0.25, green: 0.45, blue: 0.75).opacity(0.7)
        case .neonNoir:     return Color(red: 0.6,  green: 0.0,  blue: 0.8).opacity(0.6)
        case .glassPro:     return Color.white.opacity(0.18)
        case .arctic:       return Color(red: 0.75, green: 0.82, blue: 0.92)
        case .retroDark:    return Color(red: 0.3,  green: 0.28, blue: 0.22).opacity(0.8)
        case .humaniaq:     return Color(red: 0.7333, green: 0.7020, blue: 0.6510) // Warm stone border #BBB3A6
        }
    }

    public var activeBorderColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 0.0,  green: 0.75, blue: 1.0)
        case .neonNoir:     return Color(red: 1.0,  green: 0.05, blue: 0.6)
        case .glassPro:     return Color(red: 0.5,  green: 0.3,  blue: 1.0)
        case .arctic:       return Color(red: 0.15, green: 0.55, blue: 1.0)
        case .retroDark:    return Color(red: 1.0,  green: 0.6,  blue: 0.0)
        case .humaniaq:     return Color(red: 0.7608, green: 0.4196, blue: 0.2902) // Terracotta active border #C26B4A
        }
    }

    // MARK: - Top Bar
    public var topMenuBarBgColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 0.0,  green: 0.01, blue: 0.35)
        case .neonNoir:     return Color(red: 0.04, green: 0.0,  blue: 0.10)
        case .glassPro:     return Color.white.opacity(0.05)
        case .arctic:       return Color(red: 0.88, green: 0.92, blue: 0.97)
        case .retroDark:    return Color(red: 0.07, green: 0.07, blue: 0.09)
        case .humaniaq:     return Color(red: 0.9098, green: 0.8902, blue: 0.8588) // Warm paper-stone top bar #E8E3DB
        }
    }

    public var topMenuBarTextColor: Color {
        switch self {
        case .classicBlue, .neonNoir, .glassPro, .retroDark: return .white
        case .arctic: return Color(red: 0.08, green: 0.08, blue: 0.12)
        case .humaniaq: return Color(red: 0.1686, green: 0.1686, blue: 0.1568) // Dark ink text #2B2B28
        }
    }

    // MARK: - Shadows / Glow
    public var shadowColor: Color {
        switch self {
        case .classicBlue:  return Color.black.opacity(0.5)
        case .neonNoir:     return Color(red: 1.0, green: 0.0, blue: 0.5).opacity(0.4)
        case .glassPro:     return Color(red: 0.3, green: 0.1, blue: 0.8).opacity(0.35)
        case .arctic:       return Color(red: 0.5, green: 0.6, blue: 0.8).opacity(0.2)
        case .retroDark:    return Color.black.opacity(0.6)
        case .humaniaq:     return Color(red: 0.1686, green: 0.1686, blue: 0.1568).opacity(0.06) // Ink shadow
        }
    }

    // MARK: - Fonts
    public var fontName: String { "Courier" }
    public var monoFontName: String { "Courier" }

    public func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .classicBlue, .neonNoir, .retroDark:
            return .system(size: size, weight: weight, design: .monospaced)
        case .glassPro, .arctic, .humaniaq:
            return .system(size: size, weight: weight, design: .default) // Default system sans-serif font
        }
    }

    public func monoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Corner radius
    public var cornerRadius: CGFloat {
        switch self {
        case .classicBlue:  return 4
        case .neonNoir:     return 6
        case .glassPro:     return 12
        case .arctic:       return 10
        case .retroDark:    return 2
        case .humaniaq:     return 8 // Soft rounded organic corners
        }
    }

    // MARK: - Uses glass blur
    public var usesBlur: Bool {
        switch self {
        case .glassPro: return true
        default:        return false
        }
    }

    // MARK: - F-key bar style
    public var fKeyLabelColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 1.0, green: 0.85, blue: 0.2)
        case .neonNoir:     return Color(red: 1.0, green: 0.0,  blue: 0.55)
        case .glassPro:     return Color(red: 0.7, green: 0.5,  blue: 1.0)
        case .arctic:       return Color(red: 0.15, green: 0.5, blue: 1.0)
        case .retroDark:    return Color(red: 1.0, green: 0.6,  blue: 0.0)
        case .humaniaq:     return Color(red: 0.7608, green: 0.4196, blue: 0.2902) // Terracotta key label #C26B4A
        }
    }

    public var fKeyActionColor: Color {
        switch self {
        case .classicBlue:  return Color(red: 0.8, green: 0.88, blue: 1.0)
        case .neonNoir:     return Color(red: 0.85, green: 0.9, blue: 0.95)
        case .glassPro:     return Color.white.opacity(0.85)
        case .arctic:       return Color(red: 0.2,  green: 0.3,  blue: 0.5)
        case .retroDark:    return Color(red: 0.85, green: 0.85, blue: 0.8)
        case .humaniaq:     return Color(red: 0.1686, green: 0.1686, blue: 0.1568) // Ink key action #2B2B28
        }
    }

    // MARK: - Emoji / icon style
    public var folderIcon: String { "folder.fill" }
    public var fileIcon: String   { "doc.fill" }
    public var parentIcon: String { "arrow.up.circle.fill" }
}

// MARK: - ThemeManager with UserDefaults persistence
public final class ThemeManager: ObservableObject {
    private static let themeKey = "hNavigator.selectedTheme"

    @Published public var currentTheme: AppTheme

    public init() {
        // Load saved theme or fall back to glassPro
        if let saved = UserDefaults.standard.string(forKey: Self.themeKey),
           let theme = AppTheme(rawValue: saved) {
            currentTheme = theme
        } else {
            currentTheme = .glassPro
        }
    }

    public func selectTheme(_ theme: AppTheme) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentTheme = theme
        }
        UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
    }
}
