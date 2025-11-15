//
//  StarField.swift
//  Weather
//
//  Created by Paul Hudson on 09/01/2022.
//

import CoreGraphics
import Foundation

class StarField {
    var stars = [Star]()
    let leftEdge = -50.0
    var rightEdge = 350.0
    var lastUpdate = Date.now
    var lastSize = CGSize.zero

    init() {}

    func change(size: CGSize) {
        rightEdge = size.width + 50
        stars = []
        let starCount = Int(size.width * size.height / 1000)
        for _ in 1 ... starCount {
            let x = Double.random(in: leftEdge ... rightEdge)
            let y = Double.random(in: 0 ... size.height)
            let starSize = Double.random(in: 1 ... 3)
            let star = Star(x: x, y: y, size: starSize)
            stars.append(star)
        }

        lastSize = size
    }

    func update(date: Date, size: CGSize) {
        if lastSize != size {
            change(size: size)
        }
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
