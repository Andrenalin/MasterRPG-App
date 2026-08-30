//
//  StarsView.swift
//  Weather
//
//  Created by Paul Hudson on 09/01/2022.
//

import SwiftUI

struct StarsView: View {
    init(deterministic: Bool = false) {
        self._starField = State(initialValue: StarField(deterministic: deterministic))
        self.snapshotDate = deterministic ? Date(timeIntervalSinceReferenceDate: 0) : nil
    }

    @State private var starField: StarField
    let snapshotDate: Date?

    @Environment(\.accessibilityDimFlashingLights) private var accessibilityDimFlashingLights
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        TimelineView(.animation(paused: shouldPauseAnimation)) { timeline in
            Canvas { context, size in
                let renderingDate = snapshotDate ?? timeline.date
                let timeInterval = renderingDate.timeIntervalSince1970
                starField.update(date: renderingDate, size: size)
                context.addFilter(.blur(radius: 0.3))

                for (index, star) in starField.stars.enumerated() {
                    let path = Path(ellipseIn: CGRect(x: star.x, y: star.y, width: star.size, height: star.size))

                    if star.flickerInterval == 0 {
                        // flashing star
                        var flashLevel = sin(Double(index) + timeInterval * 4)
                        flashLevel = abs(flashLevel)
                        flashLevel /= 1.5
                        context.opacity = 0.5 + flashLevel
                    } else {
                        // blooming star
                        var flashLevel = sin(Double(index) + timeInterval)
                        flashLevel *= star.flickerInterval
                        flashLevel -= star.flickerInterval - 1

                        if flashLevel > 0 {
                            var contextCopy = context
                            contextCopy.opacity = flashLevel
                            contextCopy.addFilter(.blur(radius: 3))

                            contextCopy.fill(path, with: .color(white: 1))
                            contextCopy.fill(path, with: .color(white: 1))
                            contextCopy.fill(path, with: .color(white: 1))
                        }

                        context.opacity = 1
                    }

                    if index.isMultiple(of: 5) {
                        context.fill(path, with: .color(red: 1, green: 0.85, blue: 0.8))
                    } else {
                        context.fill(path, with: .color(white: 1))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .mask(
            LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
        )
    }

    private var shouldPauseAnimation: Bool {
        accessibilityReduceMotion || accessibilityDimFlashingLights
    }
}

#Preview {
    Group {
        StarsView(deterministic: true)
            .frame(width: 300, height: 150)
        StarsView(deterministic: true)
            .frame(width: 600, height: 150)
    }
    .background(.black)
}
