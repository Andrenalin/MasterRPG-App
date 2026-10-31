//
//  CloudsView.swift
//  Weather
//
//  Created by Paul Hudson on 12/11/2021.
//

import SwiftUI

struct CloudsView: View {
    init(thickness: Cloud.Thickness, topTint: Color, bottomTint: Color, deterministic: Bool = false) {
        self.thickness = thickness
        self.topTint = topTint
        self.bottomTint = bottomTint
        self.deterministic = deterministic
        _cloudGroup = State(initialValue: Self.makeCloudGroup(thickness: thickness, deterministic: deterministic))
    }

    private static func makeCloudGroup(thickness: Cloud.Thickness, deterministic: Bool) -> LazyBox<CloudGroup> {
        LazyBox { CloudGroup(thickness: thickness, deterministic: deterministic) }
    }

    let thickness: Cloud.Thickness
    let topTint: Color
    let bottomTint: Color
    let deterministic: Bool

    // Boxed in @State so the cloud particles survive `WeatherViewer.body`
    // re-evaluations triggered by unrelated model changes (rain, lightning,
    // time) instead of resetting on every edit. See CODE_AUDIT_Weather §8.1.
    @State private var cloudGroup: LazyBox<CloudGroup>

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        TimelineView(.animation(paused: accessibilityReduceMotion)) { timeline in
            Canvas { context, size in
                let cloudGroup = cloudGroup.value
                cloudGroup.update(date: timeline.date, size: size)
                context.opacity = cloudGroup.opacity

                // Note: linearGradient shading on resolved context causes memory leaks.
                // Using colorMultiply on symbols instead (see line 45).

                for cloud in cloudGroup.clouds {
                    guard let cloudImage = context.resolveSymbol(id: "cloud\(cloud.imageNumber)") else {
                        continue
                    }

                    context.translateBy(x: cloud.position.x, y: cloud.position.y)
                    context.scaleBy(x: cloud.scale, y: cloud.scale)
                    context.draw(cloudImage, at: .zero, anchor: .topLeading)
                    context.transform = .identity
                }
            } symbols: {
                ForEach(0..<CloudGroup.cloudImageCount, id: \.self) {
                    Image.bundleImage(name: "cloud\($0)")
                        .colorMultiply(topTint.interpolated(to: bottomTint, amount: 0.3))
                        .tag("cloud\($0)")
                }
            }

        }
        .ignoresSafeArea()
        .onChange(of: thickness) { _, newThickness in
            // Cloud count/opacity/scale range are baked in at construction, so a
            // genuine thickness edit still needs a fresh CloudGroup — only re-renders
            // from unrelated model changes should preserve the existing one.
            cloudGroup = Self.makeCloudGroup(thickness: newThickness, deterministic: deterministic)
        }
    }
}

#Preview {
    CloudsView(thickness: .regular, topTint: .sunriseCloudStart, bottomTint: .sunriseCloudEnd, deterministic: true)
        .frame(width: 400, height: 200)
        .background(.blue)
}
