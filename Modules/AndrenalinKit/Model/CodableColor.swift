// @copyright André Trettin

import SwiftUI

public struct CodableColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    public var color: Color {
        .init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    public init(_ color: Color) {
        #if os(macOS)
            let nsColor = NSColor(color).usingColorSpace(.sRGB)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            nsColor?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
            let uiColor = UIColor(color)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        self.red = Double(red)
        self.green = Double(green)
        self.blue = Double(blue)
        opacity = Double(alpha)
    }

    public init(red: Double, green: Double, blue: Double, opacity: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public func generateModel() -> String {
        "CodableColor(red: \(red), green: \(green), blue: \(blue), opacity: \(opacity))"
    }
}
