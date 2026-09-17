//
//  Color-Interpolation.swift
//  Weather
//
//  Created by Paul Hudson on 16/11/2021.
//

import CoreRPG
import SwiftUI
import os.log

private extension Logger {
    static let weatherColor = Logger(subsystem: subsystem, category: "WeatherColor")
}

extension Color {
    func getComponents() -> (red: Double, green: Double, blue: Double, alpha: Double) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        #if os(macOS)
            guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else {
                Logger.weatherColor.error("Failed to convert Color to sRGB NSColor; falling back to white.")
                return (1, 1, 1, 1)
            }
            nsColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
            let uiColor = UIColor(self)
            guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
                Logger.weatherColor.error("Failed to read RGBA components from Color; falling back to white.")
                return (1, 1, 1, 1)
            }
        #endif
        return (red, green, blue, alpha)
    }

    func interpolated(to other: Color, amount: Double) -> Color {
        let componentsFrom = getComponents()
        let componentsTo = other.getComponents()

        let newRed = (1 - amount) * componentsFrom.red + (amount * componentsTo.red)
        let newGreen = (1 - amount) * componentsFrom.green + (amount * componentsTo.green)
        let newBlue = (1 - amount) * componentsFrom.blue + (amount * componentsTo.blue)
        let newOpacity = (1 - amount) * componentsFrom.alpha + (amount * componentsTo.alpha)

        return Color(.displayP3, red: newRed, green: newGreen, blue: newBlue, opacity: newOpacity)
    }
}
