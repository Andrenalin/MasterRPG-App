//
//  Cloud.swift
//  Weather
//
//  Created by Paul Hudson on 12/11/2021.
//

import SwiftUI

public class Cloud {
    public enum Thickness: Int, CaseIterable, Hashable, Codable, Sendable {
        case none, thin, light, regular, thick, ultra
        
        var localizedTitle: LocalizedStringKey {
            switch self {
            case .none:
                return "None"
            case .thin:
                return "Thin"
            case .light:
                return "Light"
            case .regular:
                return "Regular"
            case .thick:
                return "Thick"
            case .ultra:
                return "Ultra"
            }
        }
    }

    public var position: CGPoint = .zero
    public let imageNumber: Int
    public let speed = Double.random(in: 4 ... 12)
    public let scale: Double

    public init(imageNumber: Int, scale: Double) {
        self.imageNumber = imageNumber
        self.scale = scale
    }

    public func change(size: CGSize) {
        let startX = Double.random(in: -(size.width + 100) ... (size.width + 100))
        let startY = Double.random(in: -50 ... (size.height / 5))
        position = CGPoint(x: startX, y: startY)
    }
}
