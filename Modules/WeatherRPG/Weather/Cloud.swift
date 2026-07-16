//
//  Cloud.swift
//  Weather
//
//  Created by Paul Hudson on 12/11/2021.
//

import Foundation
import SwiftUI

public class Cloud {
    public enum Thickness: Int, Identifiable, CaseIterable, Hashable, Codable, Sendable {
        case none, thin, light, regular, thick, ultra
        
        public var id: Int {
            rawValue
        }
        
        var localizedTitle: LocalizedStringResource {
            switch self {
            case .none:
                return LocalizedStringResource("None", bundle: .module)
            case .thin:
                return LocalizedStringResource("Thin", bundle: .module)
            case .light:
                return LocalizedStringResource("Light", bundle: .module)
            case .regular:
                return LocalizedStringResource("Regular", bundle: .module)
            case .thick:
                return LocalizedStringResource("Thick", bundle: .module)
            case .ultra:
                return LocalizedStringResource("Ultra", bundle: .module)
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
