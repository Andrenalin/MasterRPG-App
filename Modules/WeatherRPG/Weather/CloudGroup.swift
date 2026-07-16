//
//  CloudGroup.swift
//  Weather
//
//  Created by Paul Hudson on 12/11/2021.
//

import CoreGraphics
import Foundation

class CloudGroup {
    var clouds = [Cloud]()
    let opacity: Double
    let deterministic: Bool
    var lastUpdate = Date.now
    var lastSize = CGSize.zero

    init(thickness: Cloud.Thickness, deterministic: Bool = false) {
        self.deterministic = deterministic
        let cloudsToCreate: Int
        let cloudScale: ClosedRange<Double>

        switch thickness {
        case .none:
            cloudsToCreate = 0
            opacity = 1
            cloudScale = 1 ... 1

        case .thin:
            cloudsToCreate = 10
            opacity = 0.6
            cloudScale = 0.2 ... 0.4

        case .light:
            cloudsToCreate = 10
            opacity = 0.7
            cloudScale = 0.4 ... 0.6

        case .regular:
            cloudsToCreate = 15
            opacity = 0.8
            cloudScale = 0.7 ... 0.9

        case .thick:
            cloudsToCreate = 25
            opacity = 0.9
            cloudScale = 1.0 ... 1.3

        case .ultra:
            cloudsToCreate = 40
            opacity = 1
            cloudScale = 1.2 ... 1.6
        }

        for i in 0 ..< cloudsToCreate {
            let scale: Double
            if deterministic {
                let fraction = cloudsToCreate > 1 ? Double(i) / Double(cloudsToCreate - 1) : 0
                scale = cloudScale.lowerBound + (cloudScale.upperBound - cloudScale.lowerBound) * fraction
            } else {
                scale = Double.random(in: cloudScale)
            }
            let imageNumber = i % 8

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
        let delta = date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970

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
