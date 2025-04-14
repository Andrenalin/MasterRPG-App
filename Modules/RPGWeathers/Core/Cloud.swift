//
//  Cloud.swift
//  Weather
//
//  Created by Paul Hudson on 12/11/2021.
//

import SwiftUI

class Cloud {
    enum Thickness: Int, CaseIterable, Hashable, Codable {
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

    var position: CGPoint = .zero
    let imageNumber: Int
    let speed = Double.random(in: 4 ... 12)
    let scale: Double

    init(imageNumber: Int, scale: Double) {
        self.imageNumber = imageNumber
        self.scale = scale
    }

    func change(size: CGSize) {
        let startX = Double.random(in: -(size.width + 100) ... (size.width + 100))
        let startY = Double.random(in: -50 ... (size.height / 5))
        position = CGPoint(x: startX, y: startY)
    }
}
