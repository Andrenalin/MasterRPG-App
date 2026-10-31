//
//  StormView.swift
//  Weather
//
//  Created by Paul Hudson on 03/02/2022.
//

import SwiftUI

struct StormView: View {
    let type: Storm.Contents
    let direction: Angle
    let strength: Int

    // Boxed in @State so in-flight drops survive `WeatherViewer.body`
    // re-evaluations triggered by unrelated model changes instead of resetting
    // on every edit. `type`/`direction`/`strength` are baked into `drops` at
    // construction, so a genuine change to any of them still rebuilds the
    // storm — only re-renders from unrelated model changes preserve it.
    // See CODE_AUDIT_Weather §8.1.
    @State private var storm: LazyBox<Storm>

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        TimelineView(.animation(paused: accessibilityReduceMotion)) { timeline in
            Canvas { context, size in
                let storm = storm.value
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
        .onChange(of: stormKey) { _, _ in
            storm = Self.makeStorm(type: type, direction: direction, strength: strength)
        }
    }

    init(type: Storm.Contents, direction: Angle, strength: Int) {
        self.type = type
        self.direction = direction
        self.strength = strength
        _storm = State(initialValue: Self.makeStorm(type: type, direction: direction, strength: strength))
    }

    private static func makeStorm(type: Storm.Contents, direction: Angle, strength: Int) -> LazyBox<Storm> {
        LazyBox { Storm(type: type, direction: direction, strength: strength) }
    }

    private struct StormKey: Equatable {
        let type: Storm.Contents
        let direction: Angle
        let strength: Int
    }

    private var stormKey: StormKey {
        StormKey(type: type, direction: direction, strength: strength)
    }
}

#Preview {
    StormView(type: .rain, direction: .zero, strength: 200)
}
