//
//  CloudsView.swift
//  Weather
//
//  Created by Paul Hudson on 12/11/2021.
//

import SwiftUI

struct CloudsView: View {
    init(thickness: Cloud.Thickness, topTint: Color, bottomTint: Color) {
        cloudGroup = CloudGroup(thickness: thickness)
        self.topTint = topTint
        self.bottomTint = bottomTint
    }

    let cloudGroup: CloudGroup
    let topTint: Color
    let bottomTint: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                cloudGroup.update(date: timeline.date, size: size)
                context.opacity = cloudGroup.opacity

                // very expensive and memleak func
//                    resolved.shading = .linearGradient(
//                        Gradient(colors: [topTint, bottomTint]),
//                        startPoint: .zero,
//                        endPoint: CGPoint(x: 0, y: resolved.size.height)
//                    )

                for cloud in cloudGroup.clouds {
                    let cloudImage = context.resolveSymbol(id: "cloud\(cloud.imageNumber)")!
                    
                    context.translateBy(x: cloud.position.x, y: cloud.position.y)
                    context.scaleBy(x: cloud.scale, y: cloud.scale)
                    context.draw(cloudImage, at: .zero, anchor: .topLeading)
                    context.transform = .identity
                }
            } symbols: {
                ForEach(0..<8, id: \.self) {
                    Image.bundleImage(name: "cloud\($0)")
                        .colorMultiply(topTint.interpolated(to: bottomTint, amount: 0.3))
//                        .colorEffect(ShaderLibrary.cloudColor(.color(topTint), .color(bottomTint)))
                        .tag("cloud\($0)")
                }
            }

        }
        .ignoresSafeArea()
    }
}

#Preview {
    CloudsView(thickness: .regular, topTint: .sunriseCloudStart, bottomTint: .sunriseCloudEnd)
        .frame(width: 400, height: 200)
        .background(.blue)
}
