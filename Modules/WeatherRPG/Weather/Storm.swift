//
//  Storm.swift
//  Weather
//
//  Created by Paul Hudson on 03/02/2022.
//

import Foundation
import SwiftUI

public class Storm {
    public enum Contents: Int, Identifiable, CaseIterable, Hashable, Codable, Sendable {
        case none, rain, snow
        
        public var id: Int {
            rawValue
        }
        
        var localizedTitle: LocalizedStringResource {
            switch self {
            case .none:
                return LocalizedStringResource("None", bundle: .module)
            case .rain:
                return LocalizedStringResource("Rain", bundle: .module)
            case .snow:
                return LocalizedStringResource("Snow", bundle: .module)
            }
        }
    }

    var drops = [StormDrop]()
    public var lastUpdate = Date.now
    public var image: Image

    public init(type: Contents, direction: Angle, strength: Int) {
        switch type {
        case .snow:
            image = Image.bundleImage(name: "snow")
        default:
            image = Image.bundleImage(name: "rain")
        }

        for _ in 0 ..< strength {
            drops.append(StormDrop(type: type, direction: direction + .degrees(90)))
        }
    }

    public func update(date: Date, size: CGSize) {
        let delta = date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970
        let divisor = size.height / size.width

        for drop in drops {
            let radians = drop.direction.radians

            drop.x += cos(radians) * drop.speed * delta * divisor
            drop.y += sin(radians) * drop.speed * delta

            if drop.x < -0.21 {
                drop.x += 1.4
            }
            if drop.x > 1.21 {
                drop.x -= 1.4
            }

            if drop.y > 1.2 {
                drop.x = Double.random(in: -0.2 ... 1.2)
                drop.y -= 1.4
            }
        }

        lastUpdate = date
    }
}
