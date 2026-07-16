//
//  ResidueView.swift
//  Weather
//
//  Created by Paul Hudson on 13/02/2022.
//

import SwiftUI

struct ResidueView: View {
    let residue: Residue

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        TimelineView(.animation(paused: accessibilityReduceMotion)) { timeline in
            Canvas { context, size in
                residue.update(date: timeline.date, size: size)

                for drop in residue.drops {
                    var contextCopy = context

                    let xPos = drop.x * size.width
                    let yPos = drop.y * size.height

                    contextCopy.opacity = drop.opacity
                    contextCopy.translateBy(x: xPos, y: yPos)
                    contextCopy.scaleBy(x: drop.scale, y: drop.scale)

                    contextCopy.draw(residue.image, at: .zero)
                }
            }
        }
    }

    init(type: Storm.Contents, strength: Double) {
        residue = Residue(type: type, strength: strength)
    }
}

#Preview {
    ResidueView(type: .rain, strength: 200)
}
