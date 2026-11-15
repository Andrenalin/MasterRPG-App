//
//  StarField.swift
//  Weather
//
//  Created by Paul Hudson on 09/01/2022.
//

import CoreGraphics
import Foundation

class StarField {
    static let maximumStars = 600
    var stars = [Star]()
    let deterministic: Bool
    let leftEdge = -50.0
    var rightEdge = 350.0
    var lastUpdate = Date.now
    var lastSize = CGSize.zero

    init(deterministic: Bool = false) {
        self.deterministic = deterministic
    }

    func change(size: CGSize) {
        rightEdge = size.width + 50
        stars = []
        // Capped: a 1920 x 1080 screen got about 2,000 stars, each blooming one a blurred copy of
        // the context. See CODE_AUDIT_26 §7.20.
        let starCount = min(Int(size.width * size.height / 1000), Self.maximumStars)
        for index in 0 ..< starCount {
            let x: Double
            let y: Double
            let starSize: Double
            if deterministic {
                let horizontalFraction = Double((index * 47) % 997) / 996
                let verticalFraction = Double((index * 83) % 991) / 990
                x = leftEdge + (rightEdge - leftEdge) * horizontalFraction
                y = size.height * verticalFraction
                starSize = 1 + Double(index % 2)
            } else {
                x = Double.random(in: leftEdge ... rightEdge)
                y = Double.random(in: 0 ... size.height)
                starSize = Double.random(in: 1 ... 3)
            }
            let star = Star(x: x, y: y, size: starSize)
            stars.append(star)
        }

        lastSize = size
    }

    func update(date: Date, size: CGSize) {
        if lastSize != size {
            change(size: size)
        }
        guard !deterministic else { return }
        let delta = date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970

        for star in stars {
            star.x -= delta * 2

            if star.x < leftEdge {
                star.x = rightEdge
            }
        }

        lastUpdate = date
    }
}
