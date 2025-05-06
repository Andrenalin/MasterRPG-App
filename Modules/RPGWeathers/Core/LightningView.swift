//
//  LightningView.swift
//  Weather
//
//  Created by Paul Hudson on 17/03/2022.
//

import SwiftUI
internal import Combine

struct LightningView: View {
    var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var frequency: Double = 0.0
    var lightning: Lightning

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                lightning.update(date: timeline.date, in: size)

                let fullScreen = Path(CGRect(origin: .zero, size: size))
                context.fill(fullScreen, with: .color(.white.opacity(lightning.flashOpacity)))

                for _ in 0 ..< 2 {
                    for bolt in lightning.bolts {
                        var path = Path()
                        path.addLines(bolt.points)
                        context.stroke(path, with: .color(.white), lineWidth: bolt.width)
                    }

                    context.addFilter(.blur(radius: 5))
                }
            }
        }
        .ignoresSafeArea()
        .onReceive(timer) { _ in
            if frequency < 1 {
                timer.upstream.connect().cancel()
            } else {
                lightning.strike()
            }
        }
        .onTapGesture { lightning.strike() }
    }

    init(frequency: Double = 0.0, maximumBolts: Int = 4, forkProbability: Int = 20) {
        lightning = Lightning(maximumBolts: maximumBolts, forkProbability: forkProbability)
        self.frequency = frequency
        if frequency < 1 {
            timer.upstream.connect().cancel()
        } else {
            timer = Timer.publish(every: 60.0 / frequency, on: .main, in: .common).autoconnect()
        }
    }
}

struct LightningView_Previews: PreviewProvider {
    static var previews: some View {
        LightningView(frequency: 60.0, maximumBolts: 60, forkProbability: 100)
            .background(.black)
    }
}
