//
//  Lightning.swift
//  Weather
//
//  Created by Paul Hudson on 17/03/2022.
//

import SwiftUI

class Lightning {
    enum LightningState {
        case waiting, preparing, striking, fading
    }

    /// Points added per update tick, scaled by elapsed time. See CODE_AUDIT_Weather §9.14.
    private static let boltGrowthSpeed = 800.0
    /// Random horizontal/vertical wobble added to each growth step.
    private static let jitterRange = -10.0 ... 10.0
    /// Random spread applied around straight-down when a bolt forks.
    private static let forkAngleSpread = Double.pi / 4
    /// Screen-flash opacity set the instant a strike finishes.
    private static let strikeFlashOpacity = 0.6
    /// Bolt width multiplier applied once a strike finishes, before fading.
    private static let strikeWidthGrowth = 1.5
    /// Bolt width lost per second while fading out.
    private static let fadeRate = 15.0

    var bolts = [LightningBolt]()
    var state = LightningState.waiting
    var lastUpdate = Date.now
    var flashOpacity = 0.0

    var maximumBolts: Int
    var forkProbability: Int

    init(maximumBolts: Int, forkProbability: Int) {
        self.maximumBolts = maximumBolts
        self.forkProbability = forkProbability
    }

    func update(date: Date, in size: CGSize) {
        let delta = date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970
        lastUpdate = date

        switch state {
        case .waiting:
            break

        case .preparing:
            let startPosition = CGPoint(x: Double.random(in: 50 ... size.width - 50), y: 0)
            let newBolt = LightningBolt(start: startPosition, width: 5, angle: Angle.degrees(270).radians)
            bolts.append(newBolt)
            state = .striking

        case .striking:
            let speed = delta * Self.boltGrowthSpeed
            var hasFinishedStriking = true

            for bolt in bolts {
                guard var lastPoint = bolt.points.last else { continue }

                for _ in 0 ..< 5 {
                    let endX = lastPoint.x + (speed * cos(bolt.angle) + Double.random(in: Self.jitterRange))
                    let endY = lastPoint.y - (speed * sin(bolt.angle) + Double.random(in: Self.jitterRange))
                    lastPoint = CGPoint(x: endX, y: endY)
                    bolt.points.append(lastPoint)
                }

                if lastPoint.y < size.height {
                    hasFinishedStriking = false

                    if bolts.count < maximumBolts, Int.random(in: 0 ..< 100) < forkProbability {
                        let newAngle = Double.random(in: -Self.forkAngleSpread ... Self.forkAngleSpread) - .pi / 2
                        let newBolt = LightningBolt(start: lastPoint, width: bolt.width * 0.75, angle: newAngle)
                        bolts.append(newBolt)
                    }
                }
            }

            if hasFinishedStriking {
                state = .fading
                flashOpacity = Self.strikeFlashOpacity

                for bolt in bolts {
                    bolt.width *= Self.strikeWidthGrowth
                }
            }

        case .fading:
            var allFaded = true
            flashOpacity -= delta

            for bolt in bolts {
                bolt.width -= delta * Self.fadeRate

                if bolt.width > 0.05 {
                    allFaded = false
                }
            }

            if allFaded, flashOpacity <= 0 {
                state = .waiting
                bolts.removeAll(keepingCapacity: true)
            }
        }
    }

    func strike() {
        guard state == .waiting else { return }
        state = .preparing
    }

    func stop() {
        state = .waiting
        bolts.removeAll(keepingCapacity: true)
        flashOpacity = 0
        lastUpdate = .now
    }
}
