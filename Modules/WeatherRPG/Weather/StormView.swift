//
//  StormView.swift
//  Weather
//
//  Created by Paul Hudson on 03/02/2022.
//

import SwiftUI

struct StormView: View {
    let storm: Storm

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        TimelineView(.animation(paused: accessibilityReduceMotion)) { timeline in
            Canvas { context, size in
                storm.update(date: timeline.date, size: size)

                for drop in storm.drops {
                    var contextCopy = context

                    let xPos = drop.x * size.width
                    let yPos = drop.y * size.height

                    contextCopy.opacity = drop.opacity
                    contextCopy.translateBy(x: xPos, y: yPos)
                    contextCopy.rotate(by: drop.direction + drop.rotation)
                    contextCopy.scaleBy(x: drop.xScale, y: drop.yScale)
                    contextCopy.draw(storm.image, at: .zero)
                }
            }
        }
        .ignoresSafeArea()
    }

    init(type: Storm.Contents, direction: Angle, strength: Int) {
        storm = Storm(type: type, direction: direction, strength: strength)
    }
}

#Preview {
    StormView(type: .rain, direction: .zero, strength: 200)
}
