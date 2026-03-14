// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
#if SKIP
import android.graphics.Typeface
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
#elseif canImport(CoreGraphics)
import struct CoreGraphics.CGFloat
#endif

// SKIP @bridge
public struct Font : Hashable {
    #if SKIP
    public let fontImpl: @Composable () -> androidx.compose.ui.text.TextStyle

    public init(fontImpl: @Composable () -> androidx.compose.ui.text.TextStyle) {
        self.fontImpl = fontImpl
    }

    /// Return the equivalent Compose text style.
    @Composable public func asComposeTextStyle() -> androidx.compose.ui.text.TextStyle {
        return fontImpl()
    }

    // Explicit iOS-parity font metrics.
    // fontSize values are in sp and tuned to produce iOS-matching rendered heights
    // at fontScale=1.0 with Trim.Both and includeFontPadding=false.
    // renderedHeight is the single-line rendered height in dp at fontScale=1.0,
    // sourced from real-device UIAutomator measurements (not Robolectric).
    // Used by SwipeActionsBox.kt to derive layout mode thresholds.
    // lineHeight targets iOS leading (baseline-to-baseline) from Apple HIG
    // Large/default category. Wired into makeStyle as lineHeight.sp.
    // With Trim.Both, single-line height is preserved; two-line height = renderedHeight + lineHeight.
    private struct Metrics {
        let fontSize: Float
        let weight: FontWeight
        let renderedHeight: Float
        let lineHeight: Float
    }

    private static func metrics(for style: TextStyle) -> Metrics {
        switch style {
        case .largeTitle:  return Metrics(fontSize: Float(35.0),  weight: FontWeight.Normal,   renderedHeight: Float(41.0), lineHeight: Float(41.0))
        case .title:       return Metrics(fontSize: Float(29.0),  weight: FontWeight.Normal,   renderedHeight: Float(34.0), lineHeight: Float(34.0))
        case .title2:      return Metrics(fontSize: Float(23.0),  weight: FontWeight.Normal,   renderedHeight: Float(27.0), lineHeight: Float(28.0))
        case .title3:      return Metrics(fontSize: Float(20.5),  weight: FontWeight.Normal,   renderedHeight: Float(24.0), lineHeight: Float(25.0))
        case .headline:    return Metrics(fontSize: Float(18.0),  weight: FontWeight.SemiBold,  renderedHeight: Float(21.0), lineHeight: Float(22.0))
        case .subheadline: return Metrics(fontSize: Float(15.5),  weight: FontWeight.Normal,   renderedHeight: Float(18.0), lineHeight: Float(20.0))
        case .body:        return Metrics(fontSize: Float(18.0),  weight: FontWeight.Normal,   renderedHeight: Float(21.0), lineHeight: Float(22.0))
        case .callout:     return Metrics(fontSize: Float(17.0),  weight: FontWeight.Normal,   renderedHeight: Float(20.0), lineHeight: Float(21.0))
        case .footnote:    return Metrics(fontSize: Float(13.5),  weight: FontWeight.Normal,   renderedHeight: Float(16.0), lineHeight: Float(18.0))
        case .caption:     return Metrics(fontSize: Float(13.0),  weight: FontWeight.Normal,   renderedHeight: Float(15.0), lineHeight: Float(16.0))
        case .caption2:    return Metrics(fontSize: Float(12.0),  weight: FontWeight.Normal,   renderedHeight: Float(14.0), lineHeight: Float(13.0))
        }
    }

    /// Single-line rendered height in dp at fontScale=1.0 for the given text style.
    /// Used by SwipeActionsBox threshold derivation and other cross-component layout.
    public static func renderedHeight(_ style: TextStyle) -> Float {
        return metrics(for: style).renderedHeight
    }

    /// iOS baseline rendered height (pt) for the Large (default) Dynamic Type category.
    /// Single source of truth for iOS target metrics — shared with appleCompatible mode
    /// and used for cross-platform deviation calculations (e.g. swipe action thresholds).
    /// When appleCompatible is fully implemented, this will serve as the lookup for
    /// iOS target heights at the current Dynamic Type category.
    public static func iosBaselineRenderedHeight(_ style: TextStyle) -> Float {
        // The Metrics renderedHeight values are calibrated to match iOS at default scale.
        return metrics(for: style).renderedHeight
    }

    /// Returns the effective body font size as a Float (sp for `.native`,
    /// Apple dp→sp for `.appleCompatible`). Used to derive DynamicType-responsive
    /// control sizes (e.g. edit mode circles, reorder handles).
    /// Convert to dp at the call site: `with(density) { value.sp.toDp() }`.
    @Composable public static func effectiveBodyFontSize() -> Float {
        let mode = EnvironmentValues.shared.dynamicTypeMode
        switch mode {
        case .native:
            return metrics(for: .body).fontSize
        case .appleCompatible:
            let density = LocalDensity.current
            let category = appleDynamicTypeCategory(forFontScale: density.fontScale)
            let appleFontSize = appleFontSizes[TextStyle.body.rawValue][category]
            let spValue = with(density) { appleFontSize.dp.toSp() }
            return spValue.value
        }
    }

    // MARK: - Apple HIG Dynamic Type tables
    // Source: Apple Human Interface Guidelines Typography Specifications
    // Tables indexed by [TextStyle.rawValue][categoryIndex]
    // Category indices: 0=xSmall, 1=small, 2=medium, 3=large(default),
    //   4=xLarge, 5=xxLarge, 6=xxxLarge, 7=AX1, 8=AX2, 9=AX3, 10=AX4, 11=AX5

    // Font sizes in pt (≈ dp on Android)
    // Note: Float() wrappers required — Skip transpiler treats bare Double literals as Double, not Float.
    private static let appleFontSizes: [[Float]] = [
        [Float(31), Float(32), Float(33), Float(34), Float(36), Float(38), Float(40), Float(44), Float(48), Float(52), Float(56), Float(60)], // largeTitle
        [Float(25), Float(26), Float(27), Float(28), Float(30), Float(32), Float(34), Float(38), Float(43), Float(48), Float(53), Float(58)], // title
        [Float(19), Float(20), Float(21), Float(22), Float(24), Float(26), Float(28), Float(34), Float(39), Float(44), Float(50), Float(56)], // title2
        [Float(17), Float(18), Float(19), Float(20), Float(22), Float(24), Float(26), Float(31), Float(37), Float(43), Float(49), Float(55)], // title3
        [Float(14), Float(15), Float(16), Float(17), Float(19), Float(21), Float(23), Float(28), Float(33), Float(40), Float(47), Float(53)], // headline
        [Float(12), Float(13), Float(14), Float(15), Float(17), Float(19), Float(21), Float(25), Float(30), Float(36), Float(42), Float(49)], // subheadline
        [Float(14), Float(15), Float(16), Float(17), Float(19), Float(21), Float(23), Float(28), Float(33), Float(40), Float(47), Float(53)], // body
        [Float(13), Float(14), Float(15), Float(16), Float(18), Float(20), Float(22), Float(26), Float(32), Float(38), Float(44), Float(51)], // callout
        [Float(12), Float(12), Float(12), Float(13), Float(15), Float(17), Float(19), Float(23), Float(27), Float(33), Float(38), Float(44)], // footnote
        [Float(11), Float(11), Float(11), Float(12), Float(14), Float(16), Float(18), Float(22), Float(26), Float(32), Float(37), Float(43)], // caption
        [Float(11), Float(11), Float(11), Float(11), Float(13), Float(15), Float(17), Float(20), Float(24), Float(29), Float(34), Float(40)], // caption2
    ]

    // Leading (line height) in pt — baseline-to-baseline distance
    // Note: Float() wrappers required — Skip transpiler treats bare Double literals as Double, not Float.
    private static let appleLeadings: [[Float]] = [
        [Float(38), Float(39), Float(40), Float(41), Float(43), Float(46), Float(48), Float(52), Float(57), Float(61), Float(66), Float(70)], // largeTitle
        [Float(31), Float(32), Float(33), Float(34), Float(37), Float(39), Float(41), Float(46), Float(51), Float(57), Float(62), Float(68)], // title
        [Float(24), Float(25), Float(26), Float(28), Float(30), Float(32), Float(34), Float(41), Float(47), Float(52), Float(59), Float(66)], // title2
        [Float(22), Float(23), Float(24), Float(25), Float(28), Float(30), Float(32), Float(38), Float(44), Float(51), Float(58), Float(65)], // title3
        [Float(19), Float(20), Float(21), Float(22), Float(24), Float(26), Float(29), Float(34), Float(40), Float(48), Float(56), Float(62)], // headline
        [Float(16), Float(18), Float(19), Float(20), Float(22), Float(24), Float(28), Float(31), Float(37), Float(43), Float(50), Float(58)], // subheadline
        [Float(19), Float(20), Float(21), Float(22), Float(24), Float(26), Float(29), Float(34), Float(40), Float(48), Float(56), Float(62)], // body
        [Float(18), Float(19), Float(20), Float(21), Float(23), Float(25), Float(28), Float(32), Float(39), Float(46), Float(52), Float(60)], // callout
        [Float(16), Float(16), Float(16), Float(18), Float(20), Float(22), Float(24), Float(29), Float(33), Float(40), Float(46), Float(52)], // footnote
        [Float(13), Float(13), Float(13), Float(16), Float(19), Float(21), Float(23), Float(28), Float(32), Float(39), Float(44), Float(51)], // caption
        [Float(13), Float(13), Float(13), Float(13), Float(18), Float(20), Float(22), Float(25), Float(30), Float(35), Float(41), Float(48)], // caption2
    ]

    /// Maps Android fontScale to the nearest iOS Dynamic Type category index.
    /// Thresholds are midpoints between adjacent iOS body-size ratios relative
    /// to the Large (default) category's 17pt body size.
    private static func appleDynamicTypeCategory(forFontScale fontScale: Float) -> Int {
        // iOS body sizes: xSmall=14, small=15, medium=16, large=17, xLarge=19,
        // xxLarge=21, xxxLarge=23, AX1=28, AX2=33, AX3=40, AX4=47, AX5=53
        // Ratios to 17: 0.824, 0.882, 0.941, 1.000, 1.118, 1.235, 1.353,
        //               1.647, 1.941, 2.353, 2.765, 3.118
        // Thresholds = midpoints between adjacent ratios
        if fontScale < Float(0.853) { return 0 }  // xSmall
        if fontScale < Float(0.912) { return 1 }  // small
        if fontScale < Float(0.971) { return 2 }  // medium
        if fontScale < Float(1.059) { return 3 }  // large (default)
        if fontScale < Float(1.176) { return 4 }  // xLarge
        if fontScale < Float(1.294) { return 5 }  // xxLarge
        if fontScale < Float(1.500) { return 6 }  // xxxLarge
        if fontScale < Float(1.794) { return 7 }  // AX1
        if fontScale < Float(2.147) { return 8 }  // AX2
        if fontScale < Float(2.559) { return 9 }  // AX3
        if fontScale < Float(2.941) { return 10 } // AX4
        return 11                                   // AX5
    }

    private static func makeStyle(for style: TextStyle) -> @Composable () -> androidx.compose.ui.text.TextStyle {
        return {
            let mode = EnvironmentValues.shared.dynamicTypeMode
            switch mode {
            case .native:
                let m = metrics(for: style)
                return androidx.compose.ui.text.TextStyle(
                    fontSize: m.fontSize.sp,
                    fontWeight: m.weight,
                    lineHeight: m.lineHeight.sp
                )
            case .appleCompatible:
                let density = LocalDensity.current
                let category = appleDynamicTypeCategory(forFontScale: density.fontScale)
                let appleFontSize = appleFontSizes[style.rawValue][category]
                let appleLeading = appleLeadings[style.rawValue][category]
                let weight = metrics(for: style).weight
                let fontSizeSp = with(density) { appleFontSize.dp.toSp() }
                let lineHeightSp = with(density) { appleLeading.dp.toSp() }
                return androidx.compose.ui.text.TextStyle(
                    fontSize: fontSizeSp,
                    fontWeight: weight,
                    lineHeight: lineHeightSp
                )
            }
        }
    }

    public static let largeTitle = Font(fontImpl: makeStyle(for: .largeTitle))
    public static let title = Font(fontImpl: makeStyle(for: .title))
    public static let title2 = Font(fontImpl: makeStyle(for: .title2))
    public static let title3 = Font(fontImpl: makeStyle(for: .title3))
    public static let headline = Font(fontImpl: makeStyle(for: .headline))
    public static let subheadline = Font(fontImpl: makeStyle(for: .subheadline))
    public static let body = Font(fontImpl: makeStyle(for: .body))
    public static let callout = Font(fontImpl: makeStyle(for: .callout))
    public static let footnote = Font(fontImpl: makeStyle(for: .footnote))
    public static let caption = Font(fontImpl: makeStyle(for: .caption))
    public static let caption2 = Font(fontImpl: makeStyle(for: .caption2))
    #endif

    public enum TextStyle : Int, CaseIterable, Codable, Hashable {
        case largeTitle = 0 // For bridging
        case title = 1 // For bridging
        case title2 = 2 // For bridging
        case title3 = 3 // For bridging
        case headline = 4 // For bridging
        case subheadline = 5 // For bridging
        case body = 6 // For bridging
        case callout = 7 // For bridging
        case footnote = 8 // For bridging
        case caption = 9 // For bridging
        case caption2 = 10 // For bridging
    }

    public static func system(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> Font {
        #if SKIP
        let font: Font
        switch style {
        case .largeTitle:
            font = .largeTitle
        case .title:
            font = .title
        case .title2:
            font = .title2
        case .title3:
            font = .title3
        case .headline:
            font = .headline
        case .subheadline:
            font = .subheadline
        case .body:
            font = .body
        case .callout:
            font = .callout
        case .footnote:
            font = .footnote
        case .caption:
            font = .caption
        case .caption2:
            font = .caption2
        }
        guard weight != nil || design != nil else {
            return font
        }
        return Font(fontImpl: {
            font.fontImpl().copy(fontWeight: fontWeight(for: weight), fontFamily: fontFamily(for: design))
        })
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public static func system(bridgedStyle: Int, bridgedDesign: Int?, bridgedWeight: Int?) -> Font {
        let style = Font.TextStyle(rawValue: bridgedStyle) ?? .body
        let design = bridgedDesign == nil ? nil : Font.Design(rawValue: bridgedDesign!)
        let weight = bridgedWeight == nil ? nil : Font.Weight(value: bridgedWeight!)
        return system(style, design: design, weight: weight)
    }

    public static func system(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        #if SKIP
        return Font(fontImpl: {
            androidx.compose.ui.text.TextStyle(fontSize: size.sp, fontWeight: fontWeight(for: weight), fontFamily: fontFamily(for: design))
        })
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public static func system(size: CGFloat, bridgedDesign: Int?, bridgedWeight: Int?) -> Font {
        let design = bridgedDesign == nil ? nil : Font.Design(rawValue: bridgedDesign!)
        let weight = bridgedWeight == nil ? nil : Font.Weight(value: bridgedWeight!)
        return system(size: size, weight: weight, design: design)
    }

    #if SKIP
    // Cache is used not only to avoid expense of recreating font families, but also because recreated families for
    // the same name do not compare equal, causing recompositions under some configs:
    // https://github.com/skiptools/skip/issues/399
    private static var fontFamilyCache: [String: FontFamily] = [:]

    private static func findNamedFont(_ fontName: String, ctx: android.content.Context) -> FontFamily? {
        var fontFamily: FontFamily? = nil
        synchronized(fontFamilyCache) {
            fontFamily = fontFamilyCache[fontName]
        }
        guard fontFamily == nil else {
            return fontFamily
        }

        // Android font names are lowercased and separated by "_" characters, since Android resource names can take only alphanumeric characters.
        // Font lookups on Android reference the font's filename, whereas SwiftUI references the font's Postscript name
        // So the best way to have the same font lookup code work on both platforms is to name the
        // font with PS name "Some Poscript Font-Bold" as "some_postscript_font_bold.ttf", and then both iOS and Android
        // can reference it by the postscript name
        let name = fontName.lowercased().replace(" ", "_").replace("-", "_")

        //android.util.Log.i("SkipUI", "finding font: \(name)")

        // look up the font in the resource bundle for custom embedded fonts
        let fid = ctx.resources.getIdentifier(name, "font", ctx.packageName)
        if fid == 0 {
            // try to fall back on system installed fonts like "courier"
            if let typeface = Typeface.create(name, Typeface.NORMAL) {
                //android.util.Log.i("SkipUI", "found font: \(typeface)")
                fontFamily = FontFamily(typeface)
            } else {
                android.util.Log.w("SkipUI", "unable to find font named: \(fontName) (\(name))")
            }
        } else if let customTypeface = ctx.resources.getFont(fid) {
            fontFamily = FontFamily(customTypeface)
        } else {
            android.util.Log.w("SkipUI", "unable to find font named: \(name)")
        }
        if let fontFamily {
            synchronized(fontFamilyCache) {
                fontFamilyCache[fontName] = fontFamily
            }
        }
        return fontFamily
    }
    #endif

    // SKIP @bridge
    public static func custom(_ name: String, size: CGFloat) -> Font {
        #if SKIP
        return Font(fontImpl: {
            androidx.compose.ui.text.TextStyle(fontFamily: Self.findNamedFont(name, ctx: LocalContext.current), fontSize: size.sp)
        })
        #else
        fatalError()
        #endif
    }

    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        #if SKIP
        let systemFont = system(textStyle)
        return Font(fontImpl: {
            let absoluteSize = systemFont.fontImpl().fontSize.value + size
            androidx.compose.ui.text.TextStyle(fontFamily: Self.findNamedFont(name, ctx: LocalContext.current), fontSize: absoluteSize.sp)
        })
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public static func custom(_ name: String, size: CGFloat, bridgedRelativeTo textStyle: Int) -> Font {
        return custom(name, size: size, relativeTo: Font.TextStyle(rawValue: textStyle) ?? .body)
    }

    // SKIP @bridge
    public static func custom(_ name: String, fixedSize: CGFloat, unusedp: Any? = nil) -> Font {
        return Font.custom(name, size: fixedSize)
    }

    @available(*, unavailable)
    public static var `default`: Font {
        fatalError()
    }

    @available(*, unavailable)
    public init(_ font: Any /* CTFont */) {
        #if SKIP
        fontImpl = { MaterialTheme.typography.bodyMedium }
        #endif
    }

    // SKIP @bridge
    public func italic(_ isActive: Bool = true) -> Font {
        #if SKIP
        return Font(fontImpl: {
            fontImpl().copy(fontStyle: isActive ?  androidx.compose.ui.text.font.FontStyle.Italic : androidx.compose.ui.text.font.FontStyle.Normal)
        })
        #else
        fatalError()
        #endif
    }

    @available(*, unavailable)
    public func smallCaps(_ isActive: Bool = true) -> Font {
        fatalError()
    }

    @available(*, unavailable)
    public func lowercaseSmallCaps(_ isActive: Bool = true) -> Font {
        fatalError()
    }

    @available(*, unavailable)
    public func uppercaseSmallCaps(_ isActive: Bool = true) -> Font {
        fatalError()
    }

    @available(*, unavailable)
    public func monospacedDigit(_ isActive: Bool = true) -> Font {
        fatalError()
    }

    public func weight(_ weight: Font.Weight) -> Font {
        #if SKIP
        return Font(fontImpl: {
            fontImpl().copy(fontWeight: Self.fontWeight(for: weight))
        })
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public func weight(bridgedWeight: Int) -> Font {
        return weight(Font.Weight(value: bridgedWeight))
    }

    #if SKIP
    private static func fontWeight(for weight: Font.Weight?) -> FontWeight? {
        switch weight {
        case nil:
            return nil
        case .ultraLight:
            return FontWeight.Thin
        case .thin:
            return FontWeight.ExtraLight
        case .light:
            return FontWeight.Light
        case .regular:
            return FontWeight.Normal
        case .medium:
            return FontWeight.Medium
        case .semibold:
            return FontWeight.SemiBold
        case .bold:
            return FontWeight.Bold
        case .heavy:
            return FontWeight.ExtraBold
        case .black:
            return FontWeight.Black
        default:
            return FontWeight.Normal
        }
    }
    #endif

    @available(*, unavailable)
    public func width(_ width: Font.Width) -> Font {
        fatalError()
    }

    public func bold(_ isActive: Bool = true) -> Font {
        return weight(isActive ? Weight.bold : Weight.regular)
    }

    public func monospaced(_ isActive: Bool = true) -> Font {
        return design(isActive ? Design.monospaced : Design.default)
    }

    public func design(_ design: Design?) -> Font {
        #if SKIP
        return Font(fontImpl: {
            fontImpl().copy(fontFamily: Self.fontFamily(for: design))
        })
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public func design(bridgedValue: Int) -> Font {
        return design(Design(rawValue: bridgedValue))
    }

    @available(*, unavailable)
    public func leading(_ leading: Font.Leading) -> Font {
        fatalError()
    }

    // SKIP @bridge
    public func pointSize(_ size: CGFloat) -> Font {
        #if SKIP
        return Font(fontImpl: {
            fontImpl().copy(fontSize: size.sp)
        })
        #else
        fatalError()
        #endif
    }

    // SKIP @bridge
    public func scaledBy(_ factor: CGFloat) -> Font {
        #if SKIP
        return Font(fontImpl: {
            let textStyle = fontImpl()
            let pointSize = textStyle.fontSize.value * factor
            return textStyle.copy(fontSize: pointSize.sp)
        })
        #else
        fatalError()
        #endif
    }

    @available(*, unavailable)
    public func resolve(in context: Font.Context) -> Font.Resolved {
        fatalError()
    }

    public struct Context : Hashable, CustomDebugStringConvertible {
        public var debugDescription: String {
            return "Font.Context"
        }
    }

    public struct Resolved : Hashable {
        public let ctFont: Int /* CTFont */
        public let isBold: Bool
        public let isItalic: Bool
        public let pointSize: CGFloat
        public let weight: Font.Weight
        public let width: Font.Width
        public let leading: Font.Leading
        public let isMonospaced: Bool
        public let isLowercaseSmallCaps: Bool
        public let isUppercaseSmallCaps: Bool
        public let isSmallCaps: Bool
    }

    public struct Weight : Hashable {
        let value: Int
        public static let ultraLight = Weight(value: -3) // For bridging (-0.8)
        public static let thin = Weight(value: -2) // For bridging (-0.6)
        public static let light = Weight(value: -1) // For bridging (-0.4)
        public static let regular = Weight(value: 0) // For bridging (0.0)
        public static let medium = Weight(value: 1) // For bridging (0.23)
        public static let semibold = Weight(value: 2) // For bridging (0.3)
        public static let bold = Weight(value: 3) // For bridging (0.4)
        public static let heavy = Weight(value: 4) // For bridging (0.56)
        public static let black = Weight(value: 5) // For bridging (0.62)
    }

    public struct Width : Hashable {
        public var value: CGFloat

        public init(_ value: CGFloat) {
            self.value = value
        }

        public static let compressed = Width(0.8)
        public static let condensed = Width(0.9)
        public static let standard = Width(1.0)
        public static let expanded = Width(1.2)
    }

    public enum Leading : Hashable {
        case standard
        case tight
        case loose
    }

    public enum Design : Int, Hashable {
        case `default` = 0 // For bridging
        case serif = 1 // For bridging
        case rounded = 2 // For bridging
        case monospaced = 3 // For bridging
    }

    #if SKIP
    private static func fontFamily(for design: Design?) -> FontFamily? {
        switch design {
        case nil:
            return nil
        case .default:
            return FontFamily.Default
        case .serif:
            return FontFamily.Serif
        case .rounded:
            return FontFamily.Cursive
        case .monospaced:
            return FontFamily.Monospace
        }
    }
    #endif
}

public enum LegibilityWeight : Hashable {
    case regular
    case bold
}

#if !SKIP

// Unneeded stubs:

//@propertyWrapper public struct ScaledMetric<Value> : DynamicProperty where Value : BinaryFloatingPoint {
//    public init(wrappedValue: Value, relativeTo textStyle: Font.TextStyle) { fatalError() }
//    public init(wrappedValue: Value) { fatalError() }
//    public var wrappedValue: Value { get { fatalError() } }
//}

#endif
#endif
