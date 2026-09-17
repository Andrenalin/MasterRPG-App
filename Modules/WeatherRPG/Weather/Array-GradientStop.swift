//
//  Array-GradientStop.swift
//  Weather
//
//  Created by Paul Hudson on 16/11/2021.
//

import CoreRPG
import SwiftUI
import os.log

private extension Logger {
    static let weatherGradient = Logger(subsystem: subsystem, category: "WeatherGradient")
}

extension Array where Element == Gradient.Stop {
    func interpolated(amount: Double) -> Color {
        guard let initialStop = first else {
            Logger.weatherGradient.fault("Attempted to read color from an empty Gradient.Stop array; falling back to .clear.")
            return .clear
        }

        var firstStop = initialStop
        var secondStop = initialStop

        for stop in self {
            if stop.location < amount {
                firstStop = stop
            } else {
                secondStop = stop
                break
            }
        }

        let totalDifference = secondStop.location - firstStop.location

        if totalDifference > 0 {
            let relativeDifference = (amount - firstStop.location) / totalDifference
            return firstStop.color.interpolated(to: secondStop.color, amount: relativeDifference)
        } else {
            return firstStop.color.interpolated(to: secondStop.color, amount: 0)
        }
    }
}
