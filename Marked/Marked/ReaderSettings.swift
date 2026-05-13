import SwiftUI
import UIKit

enum ReaderTheme: String, CaseIterable, Identifiable {
    case light, sepia, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .sepia: return "Sepia"
        case .dark:  return "Dark"
        }
    }

    var background: Color {
        switch self {
        case .light: return Color(red: 1.00, green: 1.00, blue: 1.00)
        case .sepia: return Color(red: 0.97, green: 0.93, blue: 0.85)
        case .dark:  return Color(red: 0.10, green: 0.10, blue: 0.11)
        }
    }

    var uiBackground: UIColor {
        switch self {
        case .light: return UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        case .sepia: return UIColor(red: 0.97, green: 0.93, blue: 0.85, alpha: 1)
        case .dark:  return UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
        }
    }

    var foreground: Color {
        switch self {
        case .light: return Color(red: 0.10, green: 0.10, blue: 0.11)
        case .sepia: return Color(red: 0.27, green: 0.20, blue: 0.13)
        case .dark:  return Color(red: 0.90, green: 0.89, blue: 0.86)
        }
    }

    var uiForeground: UIColor {
        switch self {
        case .light: return UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
        case .sepia: return UIColor(red: 0.27, green: 0.20, blue: 0.13, alpha: 1)
        case .dark:  return UIColor(red: 0.90, green: 0.89, blue: 0.86, alpha: 1)
        }
    }

    var uiSecondary: UIColor {
        uiForeground.withAlphaComponent(0.65)
    }

    /// Shared card background for fenced code blocks, tables and blockquotes.
    /// Tracks the theme so it pairs with the matching syntax-highlighter theme
    /// (light `xcode` on light/sepia, dark on dark) — otherwise dark text would
    /// land on a dark card in the white/sepia reader modes.
    var codeBackground: UIColor {
        switch self {
        case .light: return UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1) // #F6F8FA
        case .sepia: return UIColor(red: 0.93, green: 0.88, blue: 0.78, alpha: 1)
        case .dark:  return UIColor(red: 37/255, green: 37/255, blue: 36/255, alpha: 1) // #252524
        }
    }

    var codeForeground: UIColor {
        switch self {
        case .light: return UIColor(red: 0.13, green: 0.16, blue: 0.20, alpha: 1)
        case .sepia: return UIColor(red: 0.27, green: 0.20, blue: 0.13, alpha: 1)
        case .dark:  return UIColor(red: 0.85, green: 0.88, blue: 0.93, alpha: 1)
        }
    }

    var inlineCodeBackground: UIColor {
        switch self {
        case .light: return UIColor(red: 0.91, green: 0.93, blue: 0.96, alpha: 1)
        case .sepia: return UIColor(red: 0.88, green: 0.82, blue: 0.71, alpha: 1)
        case .dark:  return UIColor(red: 0.20, green: 0.23, blue: 0.27, alpha: 1)
        }
    }

    var tableBorderColor: UIColor {
        uiForeground.withAlphaComponent(0.20)
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light, .sepia: return .light
        case .dark:          return .dark
        }
    }
}

enum ReaderFont: String, CaseIterable, Identifiable {
    case system
    case newYork
    case georgia
    case palatino
    case timesNewRoman
    case helvetica
    case avenirNext
    case iowanOldStyle
    case charter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:        return "System"
        case .newYork:       return "New York"
        case .georgia:       return "Georgia"
        case .palatino:      return "Palatino"
        case .timesNewRoman: return "Times New Roman"
        case .helvetica:     return "Helvetica Neue"
        case .avenirNext:    return "Avenir Next"
        case .iowanOldStyle: return "Iowan Old Style"
        case .charter:       return "Charter"
        }
    }

    func uiFont(size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        let base: UIFont
        switch self {
        case .system:
            let descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
            if #available(iOS 13.0, *) {
                let serif = descriptor.withDesign(.serif) ?? descriptor
                base = UIFont(descriptor: serif, size: size)
            } else {
                base = UIFont.systemFont(ofSize: size, weight: weight)
            }
        case .newYork:
            let descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
            let nyDescriptor = descriptor.withDesign(.serif) ?? descriptor
            base = UIFont(descriptor: nyDescriptor, size: size)
        case .georgia:
            base = UIFont(name: weight >= .semibold ? "Georgia-Bold" : "Georgia", size: size) ?? UIFont.systemFont(ofSize: size)
        case .palatino:
            base = UIFont(name: weight >= .semibold ? "Palatino-Bold" : "Palatino-Roman", size: size) ?? UIFont.systemFont(ofSize: size)
        case .timesNewRoman:
            base = UIFont(name: weight >= .semibold ? "TimesNewRomanPS-BoldMT" : "TimesNewRomanPSMT", size: size) ?? UIFont.systemFont(ofSize: size)
        case .helvetica:
            base = UIFont(name: weight >= .semibold ? "HelveticaNeue-Bold" : "HelveticaNeue", size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
        case .avenirNext:
            base = UIFont(name: weight >= .semibold ? "AvenirNext-DemiBold" : "AvenirNext-Regular", size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
        case .iowanOldStyle:
            base = UIFont(name: weight >= .semibold ? "IowanOldStyle-Bold" : "IowanOldStyle-Roman", size: size) ?? UIFont.systemFont(ofSize: size)
        case .charter:
            base = UIFont(name: weight >= .semibold ? "Charter-Bold" : "Charter-Roman", size: size) ?? UIFont.systemFont(ofSize: size)
        }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if weight >= .semibold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if traits.isEmpty { return base }
        if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }
}

@Observable
final class ReaderSettings {
    static let shared = ReaderSettings()

    private enum Key {
        static let theme = "rs.theme"
        static let fontSize = "rs.fontSize"
        static let font = "rs.font"
        static let justified = "rs.justified"
        static let lineSpacing = "rs.lineSpacing"
        static let horizontalMargin = "rs.horizontalMargin"
        static let editorFontSize = "rs.editorFontSize"
        static let editorHorizontalMargin = "rs.editorHorizontalMargin"
    }

    var theme: ReaderTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Key.theme) }
    }
    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Key.fontSize) }
    }
    var font: ReaderFont {
        didSet { UserDefaults.standard.set(font.rawValue, forKey: Key.font) }
    }
    var justified: Bool {
        didSet { UserDefaults.standard.set(justified, forKey: Key.justified) }
    }
    var lineSpacing: Double {
        didSet { UserDefaults.standard.set(lineSpacing, forKey: Key.lineSpacing) }
    }
    var horizontalMargin: Double {
        didSet { UserDefaults.standard.set(horizontalMargin, forKey: Key.horizontalMargin) }
    }
    var editorFontSize: Double {
        didSet { UserDefaults.standard.set(editorFontSize, forKey: Key.editorFontSize) }
    }
    var editorHorizontalMargin: Double {
        didSet { UserDefaults.standard.set(editorHorizontalMargin, forKey: Key.editorHorizontalMargin) }
    }

    /// Hyphenation is implicit: enabled only when text is justified.
    var hyphenated: Bool { justified }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.theme: ReaderTheme.light.rawValue,
            Key.fontSize: 18.0,
            Key.font: ReaderFont.system.rawValue,
            Key.justified: true,
            Key.lineSpacing: 6.0,
            Key.horizontalMargin: 22.0,
            Key.editorFontSize: 15.0,
            Key.editorHorizontalMargin: 16.0
        ])
        self.theme = ReaderTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .light
        self.fontSize = defaults.double(forKey: Key.fontSize)
        self.font = ReaderFont(rawValue: defaults.string(forKey: Key.font) ?? "") ?? .system
        self.justified = defaults.bool(forKey: Key.justified)
        self.lineSpacing = defaults.double(forKey: Key.lineSpacing)
        self.horizontalMargin = defaults.double(forKey: Key.horizontalMargin)
        self.editorFontSize = defaults.double(forKey: Key.editorFontSize)
        self.editorHorizontalMargin = defaults.double(forKey: Key.editorHorizontalMargin)
    }
}
