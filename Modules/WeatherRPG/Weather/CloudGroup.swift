//
//  CloudGroup.swift
//  Weather
//
//  Created by Paul Hudson on 12/11/2021.
//

import CoreGraphics
import Foundation

class CloudGroup {
    /// Number of `cloud0`...`cloud7` bundle images registered as Canvas symbols
    /// by `CloudsView`. Shared so the modulo here and the symbol range there
    /// can't drift out of sync. See CODE_AUDIT_Weather §9.15.
    static let cloudImageCount = 8

    var clouds = [Cloud]()
    let opacity: Double
    let deterministic: Bool
    var lastUpdate = Date.now
    var lastSize = CGSize.zero

    init(thickness: Cloud.Thickness, deterministic: Bool = false) {
        self.deterministic = deterministic
        let look = thickness.look
        let cloudsToCreate = look.screenCount
        let cloudScale = look.screenScale
        opacity = look.screenOpacity

        for i in 0 ..< cloudsToCreate {
            let scale: Double
            if deterministic {
                let fraction = cloudsToCreate > 1 ? Double(i) / Double(cloudsToCreate - 1) : 0
                scale = cloudScale.lowerBound + (cloudScale.upperBound - cloudScale.lowerBound) * fraction
            } else {
                scale = Double.random(in: cloudScale)
            }
            let imageNumber = i % Self.cloudImageCount

            let cloud = Cloud(imageNumber: imageNumber, scale: scale)
            clouds.append(cloud)
        }
    }

    func update(date: Date, size: CGSize) {
        if deterministic {
            guard lastSize != size else { return }
            let horizontalSpan = max(size.width + 200, 1)
            let verticalSpan = max(size.height / 5 + 50, 1)
            for (index, cloud) in clouds.enumerated() {
                let x = Double(index * 73).truncatingRemainder(dividingBy: horizontalSpan) - 100
                let y = Double(index * 37).truncatingRemainder(dividingBy: verticalSpan) - 50
                cloud.position = CGPoint(x: x, y: y)
            }
            lastSize = size
            lastUpdate = date
            return
        }

        if lastSize != size {
            clouds.forEach { $0.change(size: size) }
            lastSize = size
        }
        // Clamped like the rain: a long pause (background, a sheet) or a clock change must not
        // throw the layer far off its wrap range. See CODE_AUDIT_26 §5.131.
        let delta = min(max(date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970, 0), 0.1)

        for cloud in clouds {
            cloud.position.x -= delta * cloud.speed

            let offScreenDistance = max(size.width + 100, (size.width + 100) * cloud.scale)

            if cloud.position.x < -offScreenDistance {
                cloud.position.x = offScreenDistance
            }
        }

        lastUpdate = date
    }
}

extension Cloud.Thickness {
    /// How a cover looks, per thickness: on the 2D screen and, seen from above, on the 3D table.
    /// The one place to tune either, so the two stay in step.
    struct Look {
        /// The 2D screen: number of clouds, their opacity and their scale range.
        let screenCount: Int
        let screenOpacity: Double
        let screenScale: ClosedRange<Double>
        /// The 3D table: clouds at once and their opacity. Fewer and fainter than on the
        /// screen, so a map seen through them stays readable.
        let tableCount: Int
        let tableOpacity: Float
    }

    var look: Look {
        switch self {
        case .none:
            Look(screenCount: 0, screenOpacity: 1, screenScale: 1 ... 1, tableCount: 0, tableOpacity: 0)
        case .thin:
            Look(screenCount: 10, screenOpacity: 0.6, screenScale: 0.2 ... 0.4, tableCount: 2, tableOpacity: 0.35)
        case .light:
            Look(screenCount: 10, screenOpacity: 0.7, screenScale: 0.4 ... 0.6, tableCount: 4, tableOpacity: 0.5)
        case .regular:
            Look(screenCount: 15, screenOpacity: 0.8, screenScale: 0.7 ... 0.9, tableCount: 6, tableOpacity: 0.65)
        case .thick:
            Look(screenCount: 25, screenOpacity: 0.9, screenScale: 1.0 ... 1.3, tableCount: 9, tableOpacity: 0.8)
        case .ultra:
            Look(screenCount: 40, screenOpacity: 1, screenScale: 1.2 ... 1.6, tableCount: 12, tableOpacity: 0.9)
        }
    }
}
